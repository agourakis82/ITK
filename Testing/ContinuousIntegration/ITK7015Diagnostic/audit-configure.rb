require 'json'

trace, destination = ARGV
invocations = []
File.foreach(trace) do |line|
  entry = JSON.parse(line)
  next unless entry['cmd'] == 'execute_process'
  args = entry.fetch('args')
  args.each_index do |index|
    next unless args[index] == 'COMMAND'
    executable = args.fetch(index + 1)
    name = File.basename(executable)
    abort "Forbidden configure executable: #{executable}" if name.match?(/\A(?:python[\d.]*|pypy[\d.]*|cargo|rustc)\z/i)
    if name.match?(/\A(?:sh|bash|zsh|env)\z/) && args.join(' ').match?(/(?:^|[\s\/])(?:python[\d.]*|pypy[\d.]*|cargo|rustc)(?:\s|$)/i)
      abort "Forbidden shell configure command: #{args.inspect}"
    end
  end
  invocations << entry
end
File.write(destination, JSON.pretty_generate(invocations) + "\n")
