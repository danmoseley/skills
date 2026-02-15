# moderate-msbuild-properties

A solution with two projects where package versions are defined via MSBuild properties in a `Directory.Build.props` file. The agent must trace the property definitions, present options for each (inline the value vs. keep the property reference), and handle the cleanup of unused properties after conversion.

## Setup

```
📂 repo/
├── 📄 Platform.sln
├── 📄 Directory.Build.props
├── 📂 Api/
│   └── 📄 Api.csproj
└── 📂 Data/
    └── 📄 Data.csproj
```

`Directory.Build.props`:

```xml
<Project>
  <PropertyGroup>
    <SerilogVersion>3.1.1</SerilogVersion>
    <EFCoreVersion>8.0.11</EFCoreVersion>
    <OutputPath>$(MSBuildThisFileDirectory)artifacts\$(MSBuildProjectName)\</OutputPath>
  </PropertyGroup>
</Project>
```

`Api/Api.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog.AspNetCore" Version="$(SerilogVersion)" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="6.9.0" />
  </ItemGroup>
</Project>
```

`Data/Data.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="$(EFCoreVersion)" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="$(EFCoreVersion)" />
  </ItemGroup>
</Project>
```

Key complexity:

- `$(SerilogVersion)` and `$(EFCoreVersion)` are defined in `Directory.Build.props` and used for `PackageReference` versions
- `$(EFCoreVersion)` is used by two packages, so both must be handled together
- `Directory.Build.props` also contains `$(OutputPath)` which is unrelated and must not be removed

## Input prompt

Convert Platform.sln to Central Package Management. The package versions are currently defined as MSBuild properties in Directory.Build.props.

## What the skill should produce

- The agent traces each `$(PropertyName)` to its definition in `Directory.Build.props`
- The audit clearly shows which packages use properties vs. literal versions
- For each property, the agent asks whether to inline the value or keep the property reference
- After the user decides, the agent creates `Directory.Packages.props` accordingly
- If the user chooses to inline, the agent removes only the version-related properties from `Directory.Build.props`, preserving `$(OutputPath)` and any other non-version properties
- The agent verifies no remaining references to removed properties exist
