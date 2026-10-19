# Prueba local (sin Logstash): ejecuta init.rb y code.rb contra una lista de paths y compara con la salida del matcher de Python.
class Ev; def initialize(p); @h={"Path"=>p}; end; def get(k); @h[k]; end; def set(k,v); @h[k]=v; end; end
class Runner; def initialize(init); instance_eval(init); end; def run(code, ev); @ev = ev; instance_eval(code); end; def event; @ev; end; end
init = File.read(File.join(__dir__, "init.rb")).sub("/etc/logstash/normalized-paths.json", File.join(__dir__, "normalized-paths.json"))
r = Runner.new(init); code = File.read(File.join(__dir__, "code.rb"))
File.readlines(ARGV[0]).map(&:strip).select { |l| l.start_with?("/") }.uniq.sort.each do |p|
  ev = Ev.new(p); r.run(code, ev); puts "%s -> %s" % [p, ev.get("NormalizedPath")]
end
