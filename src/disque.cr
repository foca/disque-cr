# This is based mostly on the code found at https://github.com/soveran/disque-rb
# which is released under the following license:
#
# Copyright (c) 2015 Michel Martens
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require "resp"

class Disque
  @hosts : Array(String)

  # Connect to a Disque cluster and initialize the client.
  #
  # ```
  # client = Disque.new(["127.0.0.1:7711", "127.0.0.1:7712"], auth: "ebf12a...")
  # ```
  def initialize(hosts : Array(String), auth : String? = nil, cycle = 1000, @log : IO = STDERR)
    @hosts = hosts

    # Cluster password
    @auth = auth

    # Cycle length
    @cycle = cycle

    # Operations counter
    @count = 0

    # Known nodes
    @nodes = Hash(String, String).new

    # Connection stats
    @stats = Hash(String, Int32).new(0)

    explore!
  end

  # Connect to a Disque cluster and initialize the client.
  #
  # ```
  # client = Disque.new("127.0.0.1:7711,127.0.0.1:7712", auth: "ebf12a...")
  # ```
  #
  # See `initialize(hosts : Array(String))` for the available options.
  def initialize(hosts : String, **args)
    initialize(hosts.split(","), **args)
  end

  # Add a Job to the given queue.
  #
  # Disque's ADDJOB signature is as follows:
  #
  #     ADDJOB queue_name job <ms-timeout>
  #       [REPLICATE <count>]
  #       [DELAY <sec>]
  #       [RETRY <sec>]
  #       [TTL <sec>]
  #       [MAXLEN <count>]
  #       [ASYNC]
  #
  # You can pass any optional arguments as a hash,
  # for example:
  #
  # ```
  # disque.push("foo", "myjob", 1000, ttl: 1, async: true)
  # ```
  #
  # Note that `async` is a special case because it's just a
  # flag. That's why `true` must be passed as its value.
  def push(queue_name : String, job : String, ms_timeout : Int32, **options)
    command = ["ADDJOB", queue_name, job, ms_timeout.to_s]
    command.concat(options_to_arguments(options))

    call(command)
  end

  # Fetch new jobs from the given list of queues.
  #
  # ```
  # jobs = client.fetch(from: ["a-queue"])
  # jobs.each do |job|
  #   # do something with the job
  #
  #   client.call("ACKJOB", job.msgid)
  # end
  # ```
  #
  # Note that the version of this method that takes a block will automatically
  # call ACKJOB with the job for you.
  def fetch(from : Array(String), count : Int32 = 1, timeout : Int32 = 0)
    pick_client!

    command = [
      "GETJOB",
      "TIMEOUT", timeout.to_s,
      "COUNT", count.to_s,
      "FROM"].concat(from)

    jobs = call(command)

    if jobs
      @count += 1

      return jobs.as(Array(Resp::Reply)).map do |reply|
        job = Job.new(reply.as(Array(Resp::Reply)))

        # Update stats
        @stats[job.msgid[2,8]] += 1

        job
      end
    else
      return Array(Job).new
    end
  end

  # Fetch new jobs from the given list of queues, pass them to a block, and
  # acknowledge them as they are consumed.
  #
  # ```
  # client.fetch(from: ["a-queue"]) do |job|
  #   # do something with the job
  # end
  # ```
  def fetch(from : Array(String), count : Int32 = 1, timeout : Int32 = 0, &block)
    fetch(from, count, timeout).each do |job|
      # Process job
      yield(job)

      # Remove job
      call("ACKJOB", job.msgid)
    end
  end

  # :nodoc:
  def call(args)
    explore! if @client.nil?
    @client.as(Resp).call(args)
  rescue ex : Errno
    raise ex unless ignorable_connection_error?(ex)
    explore!
    @client.as(Resp).call(args)
  end

  # Send a command to the currently connected server.
  #
  # ```
  # client.call("CLUSTER", "MEET", "127.0.0.1", "4567")
  # ```
  def call(*args)
    call(args)
  end

  # Get information about a specific Disque::Job.
  #
  # ```
  # client.fetch(from: ["queue"]) do |job|
  #   info = client.show(job)
  #   # ... do something with the `info` Hash.
  # end
  # ```
  def show(job : Job) : Hash(String, Resp::Reply)
    info(job.msgid)
  end

  # Get information about a specific Job, given the job's ID.
  def show(id : String) : Hash(String, Resp::Reply)
    if reply = call("SHOW", id)
      keys = Array(String).new
      vals = Array(Resp::Reply).new

      reply.as(Array(Resp::Reply)).each_with_index do |elem, index|
        if index.even?
          keys << elem.as(String)
        else
          vals << elem
        end
      end

      Hash.zip(keys, vals)
    end
  end

  # Disconnect from the nodes.
  def quit
    @client.quit if @client
  end

  private def url(host)
    if @auth
      "disque://:%s@%s" % [@auth, host]
    else
      "disque://%s" % host
    end
  end

  # Collect the list of nodes and keep a connection to the node that provided
  # that information.
  private def explore!
    # Reset nodes
    @nodes.clear

    @hosts.each do |host|
      begin
        scout = Resp.new(url(host))

        result = scout.call("HELLO")

        # For keeping track of nodes and stats, we use only the
        # first eight characters of the node_id. That's because
        # those eight characters are part of the job_ids, and
        # our stats are based on that.
        prefix = result.as(Array(Resp::Reply))[1].as(String)[0,8]

        # Populate cache
        @nodes[prefix] = host
        @prefix = prefix.as(String)

        # Connect the main client to the last scouted node
        @client = Resp.new(scout.url)

        scout.quit
      rescue ex : Errno
        raise ex unless ignorable_connection_error?(ex)
        @log.puts(ex.message)
      end
    end

    raise ArgumentError.new("nodes unavailable") if @client.nil?
  end

  private def pick_client!
    if @count == @cycle
      @count = 0
      prefix, _ = @stats.max

      if prefix != @prefix
        if (host = @nodes[prefix])
          # Reconfigure main client
          @client = Resp.new(url(host))

          # Save current prefix
          @prefix = prefix

          # Reset stats for the new connection
          @stats.clear
        end
      end
    end
  end

  # Convert a Hash of options into something understandable by Resp. For the
  # special case of unary options, we assume that `foo: true` means passing just
  # "foo".
  private def options_to_arguments(options)
    arguments = Array(String).new

    options.each do |key, value|
      if value == true
        arguments.push(key.to_s)
      else
        arguments.push(key.to_s, value.to_s)
      end
    end

    arguments
  end

  # Check whether a given error is the kind of connection errors we can ignore /
  # try to explore!  again to find a new server.
  private def ignorable_connection_error?(ex : Errno)
    ex.errno & (Errno::ECONNREFUSED | Errno::EINVAL) != 0
  end
end

require "./disque/**"
