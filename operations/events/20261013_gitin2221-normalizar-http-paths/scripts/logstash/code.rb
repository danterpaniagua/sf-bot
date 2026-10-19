      path = event.get("Path")
      if path.is_a?(String) && !path.empty?
        norm = @cache[path]
        if norm.nil?
          low = path.split("?", 2)[0].split("/").reject { |s| s.empty? }.map { |s| s.downcase }
          norm = "unmatched"
          @routes.each do |segs, n, _, _|
            i = 0
            ok = true
            segs.each do |k, v|
              if k == :lit
                if i < low.length && low[i] == v
                  i += 1
                else
                  ok = false
                  break
                end
              elsif k == :one
                if i < low.length
                  i += 1
                else
                  ok = false
                  break
                end
              elsif k == :opt
                i += 1 if i < low.length
              else
                i = low.length
              end
            end
            if ok && i == low.length
              norm = n
              break
            end
          end
          if norm == "unmatched" && !low.empty? && @static.any? { |x| low.last.end_with?(x) }
            norm = "static"
          end
          @cache.clear if @cache.length >= 20000
          @cache[path] = norm
        end
        event.set("NormalizedPath", norm)
      end
