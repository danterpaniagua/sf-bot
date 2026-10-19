      require "json"
      tbl = JSON.parse(File.read("/etc/logstash/normalized-paths.json"))
      @routes = tbl["routes"].map do |r|
        segs = r["t"].split("/").reject { |s| s.empty? }.map do |s|
          if s.start_with?("{*")
            [:rest, nil]
          elsif s.start_with?("{") && s.end_with?("?}")
            [:opt, nil]
          elsif s.start_with?("{")
            [:one, nil]
          else
            [:lit, s.downcase]
          end
        end
        [segs, r["n"], segs.count { |k, _| k == :lit }, segs.count { |k, _| k != :lit }]
      end
      @routes.sort_by! { |_, _, lit, par| [-lit, par] }
      @static = (tbl["static_suffixes"] || []).map { |x| x.downcase }
      @cache = {}
