# simple-single-project

A single .NET project with three inline-versioned `PackageReference` items. No solution file, no version conflicts, no MSBuild properties. The agent should create a `Directory.Packages.props` next to the project, move all versions into it, and strip the `Version` attributes from the project file.

## Setup

```
📂 MyApp/
├── 📄 MyApp.csproj
```

`MyApp.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Logging" Version="9.0.0" />
    <PackageReference Include="System.Text.Json" Version="9.0.0" />
    <PackageReference Include="Polly" Version="8.5.0" />
  </ItemGroup>
</Project>
```

## Input prompt

Convert my project at MyApp/MyApp.csproj to use Central Package Management.

## What the skill should produce

- The agent creates `Directory.Packages.props` (in the `MyApp/` directory or asks where to place it)
- The file enables `ManagePackageVersionsCentrally` and lists all three packages alphabetically
- `Version` attributes are removed from the `.csproj`
- `dotnet restore` and `dotnet build` are run to validate
