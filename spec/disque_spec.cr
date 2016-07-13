require "./spec_helper"

NODES = [
  "127.0.0.1:6609",
  "127.0.0.1:6610",
  "127.0.0.1:6611",
  "127.0.0.1:6612",
]

DISQUE_GOOD_NODES = NODES[1, 2]
DISQUE_BAD_NODES = NODES - DISQUE_GOOD_NODES

class Disque
  getter! :stats
  getter! :prefix
  getter! :nodes
end

describe Disque do
  before do
    Disque.new(DISQUE_GOOD_NODES, auth: "testpass").call("DEBUG", "FLUSHALL")
  end

  describe "connecting" do
    it "connects via a string of comma separated hosts" do
      nodes = DISQUE_GOOD_NODES.join(",")

      c = Disque.new(nodes, auth: "testpass")

      assert_equal "PONG", c.call("PING")
      assert_equal DISQUE_GOOD_NODES.size, c.nodes.size
    end

    it "raises when it can't connect to any node" do
      log = MemoryIO.new

      assert_raise ArgumentError do
        Disque.new(DISQUE_BAD_NODES, log: log)
      end

      log_output = <<-ERR
        Error connecting to '127.0.0.1:6609': Connection refused
        Error connecting to '127.0.0.1:6612': Connection refused

        ERR

      assert_equal log_output, log.to_s
    end

    it "retries until a connection is possible" do
      log = MemoryIO.new
      c = Disque.new(NODES, auth: "testpass", log: log)

      log_output = <<-ERR
        Error connecting to '127.0.0.1:6609': Connection refused
        Error connecting to '127.0.0.1:6612': Connection refused

        ERR

      assert_equal log_output, log.to_s
      assert_equal "PONG", c.call("PING")
    end

    it "raises if auth is not provided" do
      ex = assert_raise Resp::Error do
        Disque.new(DISQUE_GOOD_NODES)
      end

      assert_equal "NOAUTH Authentication required.", ex.to_s
    end
  end

  describe "queueing and fetching jobs" do
    it "doesn't block when no jobs are available" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")
      reached = false

      c.fetch(from: ["foo"], timeout: 1) do |job|
        reached = true
      end

      assert_equal false, reached
    end

    it "queues and fetches one job" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")

      c.push("foo", "bar", 1000)

      c.fetch(from: ["foo"], count: 10) do |job|
        assert_equal "bar", job.body
      end
    end

    it "queues and fetches multiple jobs" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")

      c.push("foo", "bar", 1000)
      c.push("foo", "baz", 1000)

      jobs = ["baz", "bar"]

      c.fetch(from: ["foo"], count: 10) do |job|
        assert_equal jobs.pop, job.body
        assert_equal "foo", job.queue
      end

      assert jobs.empty?
    end

    it "puts jobs into and takes from multiple queues" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")

      c.push("foo", "bar", 1000)
      c.push("qux", "baz", 1000)

      queues = ["qux", "foo"]
      jobs = ["baz", "bar"]

      result = c.fetch(from: ["foo", "qux"], count: 10) do |job|
        assert_equal jobs.pop, job.body
        assert_equal queues.pop, job.queue
      end

      assert jobs.empty?
      assert queues.empty?
    end

    it "adds jobs with other parameters" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")
      c.push("foo", "bar", 1000, async: true, ttl: 1)

      sleep 2

      queues = ["foo"]
      jobs = ["bar"]

      result = c.fetch(from: ["foo"], count: 10, timeout: 1) do |job|
        assert_equal jobs.pop, job.body
        assert_equal queues.pop, job.queue
      end

      assert_equal ["bar"], jobs
      assert_equal ["foo"], queues
    end

    it "ACKs jobs when block is given" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")
      c.push("q1", "j1", 1000)

      job = c.fetch(from: ["q1"]) { |j| }.first

      if info = c.info(job)
        assert_equal "acked", info.fetch("state")
      end
    end

    it "doesn't ACK jobs when no block is given" do
      c = Disque.new(DISQUE_GOOD_NODES, auth: "testpass")

      c.push("q1", "j1", 1000)

      job = c.fetch(from: ["q1"]).first

      if info = c.info(job)
        assert_equal "active", info.fetch("state")
      end
    end
  end

  it "relies on the disque cluster" do
    c1 = Disque.new([DISQUE_GOOD_NODES[0]], cycle: 2, auth: "testpass")
    c2 = Disque.new([DISQUE_GOOD_NODES[1]], cycle: 2, auth: "testpass")

    c1.push("q1", "j1", 0)

    c2.fetch(from: ["q1"], count: 10) do |job|
      assert_equal "j1", job.body
    end
  end
end

describe Disque do
  before do
    Disque.new(DISQUE_GOOD_NODES, auth: "testpass").call("DEBUG", "FLUSHALL")
  end

  it "reconnects to a different node after {{cycle}} operations" do
    c1 = Disque.new(
      [DISQUE_GOOD_NODES[1], DISQUE_GOOD_NODES[0]], cycle: 2, auth: "testpass"
    )
    c2 = Disque.new(
      [DISQUE_GOOD_NODES[0], DISQUE_GOOD_NODES[1]], cycle: 2, auth: "testpass"
    )

    assert c1.prefix != c2.prefix

    c1.push("q1", "j1", 10)
    c1.push("q1", "j2", 10)
    c1.push("q1", "j3", 10)

    c2.fetch(from: ["q1"])
    c2.fetch(from: ["q1"])
    c2.fetch(from: ["q1"])

    # Client should have reconnected
    assert c1.prefix == c2.prefix
  end

  it "connects to the best node" do
    c1 = Disque.new(
      [DISQUE_GOOD_NODES[1], DISQUE_GOOD_NODES[0]], cycle: 2, auth: "testpass"
    )
    c2 = Disque.new(
      [DISQUE_GOOD_NODES[1]], cycle: 2, auth: "testpass"
    )

    assert c1.prefix != c2.prefix

    # Tamper stats to trigger a reconnection
    c1.stats[c2.prefix] = 10

    c1.push("q1", "j1", 10)
    c1.push("q1", "j2", 10)

    c2.push("q1", "j3", 10)

    c1.fetch(from: ["q1"])
    c1.fetch(from: ["q1"])
    c1.fetch(from: ["q1"])

    # Client should have reconnected
    assert c1.prefix == c2.prefix
  end
end
