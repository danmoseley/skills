# .NET MCP Server Code Examples

This file contains detailed code examples for building MCP servers in .NET.

## Tool Implementation Example

```csharp
using ModelContextProtocol;
using System.ComponentModel;

public class CalculatorTool : IMcpTool
{
    [McpToolMethod("add")]
    [Description("Adds two numbers together")]
    public Task<int> AddAsync(
        [Description("First number")] int a,
        [Description("Second number")] int b)
    {
        return Task.FromResult(a + b);
    }

    [McpToolMethod("multiply")]
    [Description("Multiplies two numbers")]
    public Task<int> MultiplyAsync(
        [Description("First number")] int a,
        [Description("Second number")] int b)
    {
        return Task.FromResult(a * b);
    }

    [McpToolMethod("divide")]
    [Description("Divides two numbers")]
    public Task<double> DivideAsync(
        [Description("Numerator")] int a,
        [Description("Denominator")] int b)
    {
        if (b == 0)
            throw new ArgumentException("Cannot divide by zero", nameof(b));
        
        return Task.FromResult((double)a / b);
    }
}
```

## Resource Implementation Example

```csharp
using ModelContextProtocol;
using System.ComponentModel;

public class ConfigResource : IMcpResource
{
    [McpResourceMethod("config://app/settings")]
    [Description("Application configuration settings")]
    public Task<ResourceContents> GetSettingsAsync()
    {
        return Task.FromResult(new ResourceContents
        {
            Uri = "config://app/settings",
            MimeType = "application/json",
            Text = "{\"timeout\": 30, \"retries\": 3}"
        });
    }

    [McpResourceMethod("config://app/version")]
    [Description("Application version information")]
    public Task<ResourceContents> GetVersionAsync()
    {
        return Task.FromResult(new ResourceContents
        {
            Uri = "config://app/version",
            MimeType = "text/plain",
            Text = "1.0.0"
        });
    }
}
```

## Unit Testing Examples

```csharp
using Xunit;

public class CalculatorToolTests
{
    [Fact]
    public async Task AddAsync_ShouldReturnSum()
    {
        var tool = new CalculatorTool();
        var result = await tool.AddAsync(5, 3);
        Assert.Equal(8, result);
    }

    [Fact]
    public async Task MultiplyAsync_ShouldReturnProduct()
    {
        var tool = new CalculatorTool();
        var result = await tool.MultiplyAsync(4, 7);
        Assert.Equal(28, result);
    }

    [Fact]
    public async Task DivideAsync_ShouldThrowOnZeroDenominator()
    {
        var tool = new CalculatorTool();
        await Assert.ThrowsAsync<ArgumentException>(() => 
            tool.DivideAsync(10, 0));
    }
}
```

## Integration Testing Example

```csharp
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol;
using Xunit;

public class McpServerIntegrationTests
{
    [Fact]
    public async Task Server_ShouldStartAndStop()
    {
        var builder = Host.CreateApplicationBuilder();
        
        builder.Services.AddMcpServer(options =>
        {
            options.ServerInfo = new ServerInfo("test-server", "1.0.0");
            options.Capabilities = new ServerCapabilities
            {
                Tools = new ToolCapabilities()
            };
        });
        
        builder.Services.AddMcpTool<CalculatorTool>();
        
        var host = builder.Build();
        
        await host.StartAsync();
        Assert.NotNull(host.Services.GetRequiredService<IMcpServer>());
        await host.StopAsync();
    }
}
```

## HTTP Server with Authentication

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using ModelContextProtocol;

var builder = WebApplication.CreateBuilder(args);

// Add JWT authentication
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://your-auth-server.com";
        options.Audience = "mcp-api";
    });

builder.Services.AddAuthorization();

builder.Services.AddMcpServer(options =>
{
    options.ServerInfo = new ServerInfo("secure-mcp-server", "1.0.0");
    options.Capabilities = new ServerCapabilities
    {
        Tools = new ToolCapabilities()
    };
});

builder.Services.AddMcpTool<CalculatorTool>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapMcp("/mcp").RequireAuthorization();

await app.RunAsync();
```

## HTTP Server with CORS

```csharp
using ModelContextProtocol;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins("https://your-client-app.com", "https://another-client.com")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

builder.Services.AddMcpServer(options =>
{
    options.ServerInfo = new ServerInfo("cors-enabled-server", "1.0.0");
    options.Capabilities = new ServerCapabilities
    {
        Tools = new ToolCapabilities()
    };
});

builder.Services.AddMcpTool<CalculatorTool>();

var app = builder.Build();

app.UseCors();
app.MapMcp("/mcp");

await app.RunAsync();
```

## Docker Deployment Example

### Dockerfile

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["MyMcpServer.csproj", "./"]
RUN dotnet restore
COPY . .
RUN dotnet build -c Release -o /app/build

FROM build AS publish
RUN dotnet publish -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "MyMcpServer.dll"]
```

### docker-compose.yml

```yaml
version: '3.8'
services:
  mcp-server:
    build: .
    ports:
      - "8080:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```
