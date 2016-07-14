require "../src/disque"

nodes = ENV["DISQUE_NODES"]

if nodes.nil?
  abort "You need to set the DISQUE_NODES environment variable"
end

client = Disque.new(nodes)

i = 0
loop do
  queue = ["example-queue-1", "example-queue-2"].sample
  client.push(queue, "Message #{i}", 1000)

  i += 1
  sleep 2
end
