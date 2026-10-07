<%@ WebHandler Language="C#" Class="HealthCheckHandler" %>
using System;
using System.Configuration;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Threading;
using System.Web;

public class HealthCheckHandler : IHttpHandler
{
    private const int DbTimeoutSeconds = 2;
    private const double DefaultCpuThreshold = 80;
    private const double DefaultMemThreshold = 80;

    public void ProcessRequest(HttpContext context)
    {
        try
        {
            double cpu = GetCpuUsage();
            double mem = GetMemoryUsage();
            double queue = GetRequestQueueLength();
            bool dbOk = CheckDatabase(out string dbError);
            double cpuThreshold = GetThreshold("HealthCheck_CpuThreshold", DefaultCpuThreshold);
            double memThreshold = GetThreshold("HealthCheck_MemThreshold", DefaultMemThreshold);

            string status;
            int httpStatus;

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
                "{{\"status\":\"{0}\",\"cpu\":{1},\"memory\":{2},\"requestsQueued\":{3},\"database\":\"{4}\"{5}}}",
                status,
                cpu.ToString("0.##"),
                mem.ToString("0.##"),
                queue.ToString("0.##"),
                dbOk ? "Healthy" : "Error",
                dbOk ? "" : ",\"databaseError\":\"" + dbError.Replace("\"", "'") + "\""
            );

            context.Response.StatusCode = httpStatus;
            context.Response.ContentType = "application/json";
            context.Response.Write(json);
        }
        catch (Exception ex)
        {
            context.Response.StatusCode = 500;
            context.Response.ContentType = "application/json";
            context.Response.Write("{\"status\":\"Error\",\"message\":\"" + ex.Message.Replace("\"", "'") + "\"}");
        }
    }

    public bool IsReusable { get { return false; } }

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

    private bool CheckDatabase(out string error)
    {
        error = null;
        try
        {
            var connStringSetting = ConfigurationManager.ConnectionStrings["SmartFran.Solution.SmartLoyalty.Data.Context.SmartLoyaltyContext"];
            if (connStringSetting == null)
            {
                error = "Connection string not found in configuration";
                return false;
            }

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
