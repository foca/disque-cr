require "./spec_helper"

NODES = [
  "127.0.0.1:7700",
  "127.0.0.1:7711",
  "127.0.0.1:7722",
  "127.0.0.1:7744",
]

DISQUE_GOOD_NODES = NODES[1, 2]
DISQUE_BAD_NODES = NODES - DISQUE_GOOD_NODES

describe Disque do
  it "doesn't block when no jobs are available" do
    c = Disque.new(DISQUE_GOOD_NODES)
    reached = false

    c.fetch(from: ["foo"], timeout: 1) do |job|
      reached = true
    end

    assert_equal false, reached
  end

  it "queues and fetches one job" do
    c = Disque.new(DISQUE_GOOD_NODES)

    c.push("foo", "bar", 1000)

    c.fetch(from: ["foo"], count: 10) do |job|
      assert_equal "bar", job.body
    end
  end

  it "queues and fetches multiple jobs" do
    c = Disque.new(DISQUE_GOOD_NODES)

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
    c = Disque.new(DISQUE_GOOD_NODES)

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

  it "add jobs with other parameters" do
    c = Disque.new(DISQUE_GOOD_NODES)
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

  it "ack jobs when block is given" do
    c = Disque.new(DISQUE_GOOD_NODES)
    c.push("q1", "j1", 1000)

    job = c.fetch(from: ["q1"]) { |j| }.first

    if info = c.info(job)
      assert_equal "acked", info.fetch("state")
    end
  end

  it "don't ack jobs when no block is given" do
    c = Disque.new(DISQUE_GOOD_NODES)

    c.push("q1", "j1", 1000)

    job = c.fetch(from: ["q1"]).first

    if info = c.info(job)
      assert_equal "active", info.fetch("state")
    end
  end
end