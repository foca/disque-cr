# disque.cr

Crystal client for [Disque](https://github.com/antirez/disque), an in-memory,
distributed job queue.

## Installation

Add this to your application's `shard.yml`:

``` yaml
dependencies:
  disque:
    github: foca/disque
    branch: master
```

## Usage

Create a new Disque client by passing a list of nodes:

``` crystal
client = Disque.new(["127.0.0.1:7711", "127.0.0.1:7712", "127.0.0.1:7713"])
```

Alternatively, you can pass a single string with comma-separated nodes:

``` crystal
client = Disque.new("127.0.0.1:7711,127.0.0.1:7712,127.0.0.1:7713")
```

Using a single string is useful if you are receiving the list of nodes from an
environment variable.

If the nodes are password protected, you can pass the `AUTH` string:

``` crystal
client = Disque.new("127.0.0.1:7711", auth: "e727d1464a...")
```

The client keeps track of which nodes are providing more jobs, and after a given
number operations it tries to connect to the preferred node. The number of
operations for each cycle defaults to 1000, but it can be configured:

``` crystal
client = Disque.new("127.0.0.1:7711", cycle: 20000)
```

Now you can add jobs:

``` crystal
client.push("foo", "bar", 100)
```

It will push the job `"bar"` to the queue `"foo"` with a timeout of 100 ms, and
return the id of the job if it was received and replicated in time.

Disque's `ADDJOB` signature is as follows:

```
ADDJOB queue_name job <ms-timeout>
  [REPLICATE <count>]
  [DELAY <sec>]
  [RETRY <sec>]
  [TTL <sec>]
  [MAXLEN <count>]
  [ASYNC]
```

You can pass any optional arguments as a hash, for example:

``` crystal
disque.push("foo", "myjob", 1000, ttl: 1, async: true)
```

Note that `async` is a special case because it's just a flag. That's why `true`
must be passed as its value.

Then, your workers will do something like this:

``` crystal
loop do
  client.fetch(from: ["foo"]) do |job|
    # Do something with `job`
  end
end
```

The `fetch` command receives an array of queues, and optionally a `timeout` (in
    milliseconds) and the `count` of jobs to retrieve:

``` crystal
client.fetch(from: ["bar", "baz"], count: 10, timeout: 2000)
```

## Example

Run in a terminal:

    DISQUE_NODES=127.0.0.1:7711 crystal run example/worker.cr

And in another:

    DISQUE_NODES=127.0.0.1:7711 crystal run example/timer.cr

Adjust `DISQUE_NODES` to your local-running instances of Disque.

## License

This is released under the MIT license. See [LICENSE](./LICENSE) for details.
The code was mostly adapted from [soveran][]'s [disque-rb][] project.

[soveran]: https://github.com/soveran
[disque-rb]: https://github.com/soveran/disque-rb
