# Wraps a Job returned by a GETJOB operation.
struct Disque::Job
  getter :queue, :msgid, :body

  def initialize(@queue, @msgid, @body)
  end

  def initialize(reply : Array(Resp::Reply))
    queue, msgid, body = reply

    @queue = queue.as(String)
    @msgid = msgid.as(String)
    @body = body.as(String)
  end
end
