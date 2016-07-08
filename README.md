# disque.cr

Crystal client for [Disque](https://github.com/antirez/disque)

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  disque:
    github: foca/disque
```

## Usage

```crystal
require "disque"

client = Disque.new(["127.0.0.1:7711","127.0.0.1:7712"])
client.push("queue", "some-job", 1000)

loop do
  client.fetch(from: ["queue"], timeout: 1) do |job|
    # here you can access `job.body` for the contents of your job.
  end
end
```

## License

This is based mostly on [soveran][]'s [disque-rb][] project. All I did was
translate it to Crystal.

[soveran]: https://github.com/soveran
[disque-rb]: https://github.com/soveran/disque-rb
