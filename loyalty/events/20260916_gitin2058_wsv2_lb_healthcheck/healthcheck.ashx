<%@ WebHandler Language="C#" Class="HealthCheckHandler" %>
using System;
using System.Configuration;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Net.Sockets;
using System.Threading;
using System.Web;

public class HealthCheckHandler : IHttpHandler
{
    private const int DbTimeoutSeconds = 2;
    private const int RedisTimeoutSeconds = 2;
    private const double DefaultCpuThreshold = 80;
    private const double DefaultMemThreshold = 80;

    public void ProcessRequest(HttpContext context)
    {
        try
        {
            double cpu = GetCpuUsage();
            double mem = GetMemoryUsage();
            double queue = GetRequestQueueLength();
            bool dbOk = CheckDatabase(out string dbError, out long dbMs);
            bool redisOk = CheckRedis(out string redisError, out long redisMs);
            double cpuThreshold = GetThreshold("HealthCheck_CpuThreshold", DefaultCpuThreshold);
            double memThreshold = GetThreshold("HealthCheck_MemThreshold", DefaultMemThreshold);

            string status;
            int httpStatus;

            // Redis failure is a supported degraded mode (app falls back to DB directly,
            // see RedisCacheService.GetOrSetCache) — reported, but does not remove this
            // backend from LB rotation on its own. DB failure and CPU/RAM over threshold
            // do, same as MobileAppService's handler (GITIN-1228).
            if (!dbOk)
            {
                status = "Error";
                httpStatus = 500;
            }
            else if (cpu > cpuThreshold || mem > memThreshold)
            {
                status = "Warning";
                httpStatus = 400;
            }
            else
            {
                status = "Healthy";
                httpStatus = 200;
            }

            string json = string.Format(
                "{{\"status\":\"{0}\",\"cpu\":{1},\"memory\":{2},\"requestsQueued\":{3},\"database\":{{\"healthy\":{4},\"message\":\"{5}\",\"responseTimeMs\":{6}}},\"redis\":{{\"healthy\":{7},\"message\":\"{8}\",\"responseTimeMs\":{9}}},\"timestamp\":\"{10}\"}}",
                status,
                cpu.ToString("0.##"),
                mem.ToString("0.##"),
                queue.ToString("0.##"),
                dbOk.ToString().ToLower(),
                EscapeJson(dbOk ? "Connected" : dbError),
                dbMs,
                redisOk.ToString().ToLower(),
                EscapeJson(redisOk ? "Connected" : redisError),
                redisMs,
                DateTime.UtcNow.ToString("o")
            );

            context.Response.StatusCode = httpStatus;
            context.Response.ContentType = "application/json";
            context.Response.Write(json);
        }
        catch (Exception ex)
        {
            context.Response.StatusCode = 500;
            context.Response.ContentType = "application/json";
            context.Response.Write("{\"status\":\"Error\",\"message\":\"" + EscapeJson(ex.Message) + "\"}");
        }
    }

    public bool IsReusable { get { return false; } }

    private static string EscapeJson(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        return s.Replace("\\", "\\\\").Replace("\"", "'").Replace("\r", "").Replace("\n", " ");
    }

    private double GetThreshold(string appSettingKey, double defaultValue)
    {
        string raw = ConfigurationManager.AppSettings[appSettingKey];
        double parsed;
        if (!string.IsNullOrEmpty(raw) && double.TryParse(raw, out parsed))
        {
            return parsed;
        }
        return defaultValue;
    }

    private bool CheckDatabase(out string error, out long elapsedMs)
    {
        error = null;
        elapsedMs = 0;
        try
        {
            // Direct lookup — not a fuzzy Name.Contains() scan. The platform-wide
            // ConnectionStrings.config has several entries whose names all contain
            // "SmartFran"/"Context" (MembershipContext, ScheduleContext, etc.) —
            // a substring match can silently grab the wrong database.
            var connStringSetting = ConfigurationManager.ConnectionStrings["SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext"];
            if (connStringSetting == null)
            {
                error = "Connection string not found in configuration";
                return false;
            }

            var sw = Stopwatch.StartNew();
            var builder = new SqlConnectionStringBuilder(connStringSetting.ConnectionString)
            {
                ConnectTimeout = DbTimeoutSeconds
            };

            using (var conn = new SqlConnection(builder.ConnectionString))
            {
                conn.Open();
                using (var cmd = new SqlCommand("SELECT 1", conn))
                {
                    cmd.CommandTimeout = DbTimeoutSeconds;
                    cmd.ExecuteScalar();
                }
            }
            sw.Stop();
            elapsedMs = sw.ElapsedMilliseconds;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private bool CheckRedis(out string error, out long elapsedMs)
    {
        error = null;
        elapsedMs = 0;
        try
        {
            // Direct lookup, matching the real app's own config keys
            // (SmartFran.Solution.SmartLoyalty.Service.SaleProviderContext.RedisCacheService).
            string connectionString = ConfigurationManager.AppSettings["RedisConnection"];
            if (string.IsNullOrEmpty(connectionString))
            {
                error = "RedisConnection setting not found";
                return false;
            }

            string hostPart = connectionString.Split(',')[0].Trim();
            string[] hostPortParts = hostPart.Split(':');
            string host = hostPortParts[0];
            int port = 6380;
            if (hostPortParts.Length > 1)
            {
                int.TryParse(hostPortParts[1], out port);
            }

            var sw = Stopwatch.StartNew();
            using (var client = new TcpClient())
            {
                IAsyncResult result = client.BeginConnect(host, port, null, null);
                bool connected = result.AsyncWaitHandle.WaitOne(RedisTimeoutSeconds * 1000);
                if (!connected)
                {
                    error = "Connection timeout";
                    return false;
                }
                client.EndConnect(result);
            }
            sw.Stop();
            elapsedMs = sw.ElapsedMilliseconds;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private double GetCpuUsage()
    {
        try
        {
            using (var cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total"))
            {
                cpuCounter.NextValue();
                Thread.Sleep(500);
                return Math.Round(cpuCounter.NextValue(), 2);
            }
        }
        catch
        {
            return 0;
        }
    }

    private double GetRequestQueueLength()
    {
        try
        {
            using (var queueCounter = new PerformanceCounter("ASP.NET", "Requests Queued"))
            {
                return queueCounter.NextValue();
            }
        }
        catch
        {
            return 0;
        }
    }

    private double GetMemoryUsage()
    {
        try
        {
            using (var committedBytes = new PerformanceCounter("Memory", "Committed Bytes"))
            using (var commitLimit = new PerformanceCounter("Memory", "Commit Limit"))
            {
                float committed = committedBytes.NextValue();
                float limit = commitLimit.NextValue();

                if (limit <= 0) return 0;
                double percent = (committed / limit) * 100.0;
                return Math.Max(0, Math.Min(100, Math.Round(percent, 2)));
            }
        }
        catch
        {
            return 0;
        }
    }
}
