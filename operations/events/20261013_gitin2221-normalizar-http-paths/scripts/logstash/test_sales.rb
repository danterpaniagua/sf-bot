require "json"
class Ev; def initialize(h); @h=h; end; def get(k); @h[k]; end; def set(k,v); @h[k]=v; end; end
class Runner; def run(code, ev); @ev=ev; instance_eval(code); end; def event; @ev; end; end
conf = File.read(File.join(__dir__, "test-sales-pipeline.conf"))
code = conf[/code => '\n(.*?)\n    '/m, 1]
exp = JSON.parse(File.read(File.join(__dir__, "test-sales-expected.json")))
bad = 0
File.readlines(File.join(__dir__, "test-sales-events.jsonl")).each do |l|
  h = JSON.parse(l); ev = Ev.new(h); Runner.new.run(code, ev)
  ope = ev.get("ElapsedMillisecondsOpe"); old = ev.get("ElapsedMilliseconds"); want = exp[h["id"].to_s]
  raw = (JSON.parse(h["Properties"]) rescue {})["ElapsedMilliseconds"] if h["Properties"]
  want_old = raw.is_a?(Numeric) ? raw : nil          # el campo original solo se llena como antes: si ya venia numerico
  ok_ope = want.nil? ? ope.nil? : (ope.is_a?(Numeric) && (ope - want).abs < 1e-9)
  ok_old = want_old.nil? ? old.nil? : (old.is_a?(Numeric) && (old - want_old).abs < 1e-9)
  bad += 1 unless ok_ope && ok_old
  puts "%-3s %-34s Ope=%-9s original=%-5s %s" % [h["id"], (raw.nil? ? "(sin valor)" : raw.inspect)[0,34], ope.inspect, old.inspect, ok_ope && ok_old ? "OK" : "DIFERENTE"]
end
puts "diferencias: #{bad}"
