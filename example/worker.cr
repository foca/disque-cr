require "../src/disque"

nodes = ENV["DISQUE_NODES"]

if nodes.nil?
  abort "You need to set the DISQUE_NODES environment variable"
end

client = Disque.new(nodes)

loop do
  client.fetch(from: ["example-queue-1", "example-queue-2"], timeout: 1) do |job|
    puts "#{job.queue} => #{job.body}"
  end
end
