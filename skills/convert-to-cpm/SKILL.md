---
name: convert-to-cpm
description: Convert .NET projects and solutions to use NuGet Central Package Management (CPM). Use when the user wants to centralize package versions into a Directory.Packages.props file, remove Version attributes from PackageReference items, and adopt CPM across a repository, solution, or single project.
---

# Convert to Central Package Management

Migrate .NET projects from per-project package versioning to NuGet Central Package Management (CPM). CPM centralizes all package versions into a single `Directory.Packages.props` file, making version governance and upgrades easier across multi-project repositories.

## When to Use

- The user wants to adopt Central Package Management for a .NET repository, solution, or project
- Package versions are scattered across many `.csproj`, `.fsproj`, or `.vbproj` files and the user wants a single source of truth
- The user mentions `Directory.Packages.props`, CPM, or centralizing NuGet versions

## When Not to Use

- The repository already has CPM enabled (a `Directory.Packages.props` with `ManagePackageVersionsCentrally` set to `true` already exists)
- The user is working with `packages.config`-based projects (classic NuGet); those must first be migrated to `PackageReference`
- The user wants to manage versions via a custom MSBuild property file without using the CPM feature

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Scope | Yes | A project file, solution file, or repository root to convert |
| Version conflict strategy | No | How to resolve cases where the same package has different versions across projects (default: use highest version) |

## Workflow

### Step 1: Determine the scope

Identify whether the conversion targets a single project, a solution, or an entire repository.

- **Single project**: The user specifies a `.csproj`, `.fsproj`, or `.vbproj` file.
- **Solution**: The user specifies a `.sln` or `.slnx` file. List the projects it contains with `dotnet sln list`.
- **Repository root**: No specific file is given. Recursively find all project files (`*.csproj`, `*.fsproj`, `*.vbproj`) under the current directory.

If the scope is unclear, ask the user to clarify which projects should be included.

### Step 2: Check for existing CPM configuration

Search for any existing `Directory.Packages.props` file in the scope or any ancestor directory. Use a recursive file search appropriate for the platform:

```bash
# Unix/macOS
find . -name "Directory.Packages.props" -type f

# Windows (PowerShell)
Get-ChildItem -Recurse -Filter "Directory.Packages.props"
```

If a `Directory.Packages.props` already exists and contains `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>`:

- **If converting additional projects under the same root**: Continue to step 3 to process the remaining projects and add any missing `PackageVersion` entries.
- **If CPM is already fully enabled for all in-scope projects**: Inform the user that CPM is already active and stop.

If a `Directory.Packages.props` exists but does not enable CPM, ask the user whether to add the CPM property to the existing file or create a new one.

### Step 3: Audit package references

For each in-scope project file, extract all `<PackageReference>` items and their `Version` attributes. Build a consolidated list of all packages and versions across all projects.

Watch for these complexities and flag them to the user:

1. **Version set via MSBuild property**: If a `PackageReference` uses a property for its version (e.g., `Version="$(SomePackageVersion)"`), trace the property definition. If the property is defined in a `Directory.Build.props`, `.props` import, or the project file itself, note it for the user. These require manual decisions about whether to replace the property with a literal version in `Directory.Packages.props` or to keep the property and use it within `Directory.Packages.props`.

2. **Conditional PackageReference items**: If a `PackageReference` is inside a conditional `<ItemGroup>` (e.g., `Condition="'$(TargetFramework)' == 'net8.0'"`), the version must still be centralized. The `PackageVersion` entry in `Directory.Packages.props` can use the same condition, or the project can use `VersionOverride` if the condition is project-specific.

3. **Same package with different versions**: If the same package ID appears with different versions across projects, record all versions. The default strategy is to use the highest version. Ask the user to confirm the chosen version if the versions differ by a major version number, as this may indicate intentional pinning. For minor or patch-level differences, prefer the highest version but note the change to the user — a patch-level difference may indicate a security fix.

4. **Known security advisories**: If a package version is known to have security vulnerabilities (e.g., from nuget.org advisory data or the user's `dotnet list package --vulnerable` output), flag the vulnerable version and recommend upgrading at least to the minimum patched version. Do not silently keep a vulnerable version even if a project pins to it.

5. **Packages without a Version attribute**: These may already be managed by CPM from a parent directory or may be using a default version. Verify whether a `Directory.Packages.props` in an ancestor directory already provides the version.

6. **PackageReference items in imported .props/.targets files**: Scan for `<Import>` elements in project files and `Directory.Build.props` to discover shared `.props` or `.targets` files that may contain `PackageReference` items. Search those imported files for package references — they need the same treatment but modifying shared build files has broader impact. Flag these to the user.

7. **VersionOverride already in use**: If any project already uses `VersionOverride`, note it — this suggests partial CPM adoption may already be in progress.

Present the audit results to the user before proceeding. Include:
- Total number of projects and packages found
- A table showing each package, its version(s), and which projects use it
- Any packages with version conflicts across projects
- Any known security advisories on discovered versions
- Any complexities from the list above that require decisions

### Step 4: Create or update Directory.Packages.props

Determine the correct location for `Directory.Packages.props`:

- **Repository scope**: Place at the repository root (same directory as `.git`).
- **Solution scope**: Place in the solution directory.
- **Single project scope**: Default to the project directory. If the project is inside a repository with other projects that may be converted later, ask the user whether to place it at the repository root instead.

If the file does not exist, create it using the .NET CLI (available in .NET 8+):

```bash
dotnet new packagesprops
```

This generates a `Directory.Packages.props` with `ManagePackageVersionsCentrally` set to `true`. If the CLI template is not available, create the file manually:

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <!-- PackageVersion items will be added here -->
  </ItemGroup>
</Project>
```

Add a `<PackageVersion>` entry for each unique package, using the resolved version from step 3. Sort entries alphabetically by package ID for readability:

```xml
<PackageVersion Include="Microsoft.Extensions.Logging" Version="9.0.0" />
<PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />
```

If the same package needs different versions for different target frameworks, use MSBuild conditions:

```xml
<PackageVersion Include="PackageA" Version="1.0.0" Condition="'$(TargetFramework)' == 'netstandard2.0'" />
<PackageVersion Include="PackageA" Version="2.0.0" Condition="'$(TargetFramework)' == 'net8.0'" />
```

Ask the user before using conditional versions — it may be preferable to standardize on a single version.

### Step 5: Update project files and shared build files

For each in-scope project file and any shared `.props` or `.targets` files that contain `PackageReference` items (identified in step 3), remove the `Version` attribute from every `<PackageReference>` that now has a corresponding `<PackageVersion>` in `Directory.Packages.props`.

**Before:**
```xml
<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
```

**After:**
```xml
<PackageReference Include="Newtonsoft.Json" />
```

Preserve all other attributes on `PackageReference` items (such as `PrivateAssets`, `IncludeAssets`, `ExcludeAssets`, `GeneratePathProperty`, `Aliases`). When a `PackageReference` is inside a conditional `<ItemGroup>` (e.g., with a `Condition` attribute for target framework), preserve the `ItemGroup` and its condition — only remove the `Version` attribute from the `PackageReference` within it.

If a project intentionally needs a different version than the centrally defined one, use `VersionOverride` instead of removing the `Version` attribute:

```xml
<PackageReference Include="Newtonsoft.Json" VersionOverride="12.0.3" />
```

Ask the user before applying `VersionOverride` — in most cases, version alignment is preferred.

### Step 6: Handle properties that defined versions

For any `PackageReference` that used an MSBuild property for its version (identified in step 3):

1. **Determine if the property is used elsewhere.** Search all project files, `.props`, and `.targets` files in scope for references to the property name (e.g., grep for `$(SomeVersion)`). If it appears only in `PackageReference` version attributes, it is safe to remove after inlining.

2. If the property is only used for package versioning and is defined in a file within scope (e.g., `Directory.Build.props`), ask the user whether to:
   - Replace the property usage with a literal version in `Directory.Packages.props` and remove the property definition (done later in step 8)
   - Keep the property and reference it from `Directory.Packages.props` (e.g., `<PackageVersion Include="PackageA" Version="$(PackageAVersion)" />`)

3. If the property is used for other purposes beyond package versioning, do not remove it. Use the property value in `Directory.Packages.props` and inform the user.

4. If the property is defined outside the conversion scope (e.g., in a parent repository's build infrastructure), flag it to the user and skip that package. Add a comment in `Directory.Packages.props`:

```xml
<!-- PackageA: version managed externally via $(PackageAVersion) in [file path] -->
```

**Import order note:** If keeping a property reference in `Directory.Packages.props` (e.g., `Version="$(PackageAVersion)"`), the property must be defined in a file that MSBuild evaluates before `Directory.Packages.props`. Properties in `Directory.Build.props` satisfy this requirement because MSBuild imports `Directory.Build.props` before `Directory.Packages.props`.

### Step 7: Restore and validate

Run `dotnet restore` on the solution or each project to verify the conversion:

```bash
dotnet restore
```

For multi-target framework projects (those with `<TargetFrameworks>` containing multiple TFMs), verify restore works for each framework. If restoration errors are framework-specific, the solution may require conditional `<PackageVersion>` entries or `VersionOverride` for specific projects.

Check for these specific errors:

- **NU1008**: A `PackageReference` still has a `Version` attribute when CPM is enabled. Fix by removing the `Version` attribute or converting it to `VersionOverride`.
- **NU1010**: A `PackageReference` has no corresponding `PackageVersion` entry. Fix by adding the missing entry to `Directory.Packages.props`.
- **NU1507**: Multiple package sources are configured without package source mapping. Inform the user they should consider configuring [package source mapping](https://learn.microsoft.com/en-us/nuget/consume-packages/package-source-mapping).

If `dotnet restore` succeeds, also run `dotnet build` to verify the project builds:

```bash
dotnet build
```

### Step 8: Clean up obsolete version properties

If version-related MSBuild properties were replaced with literal values in `Directory.Packages.props` (from step 6, option where the user chose to inline the version), remove the now-unused property definitions from `Directory.Build.props` or other files where they were defined.

Before removing any property, search all project files, `.props`, and `.targets` files for remaining references to verify the property is not used for any other purpose:

```bash
# Unix/macOS
grep -r '$(PropertyName)' --include='*.csproj' --include='*.props' --include='*.targets' .

# Windows (PowerShell)
Get-ChildItem -Recurse -Include *.csproj,*.props,*.targets | Select-String '$(PropertyName)'
```

Only remove a property if it has zero remaining references outside its own definition.

### Step 9: Review the final state

Present a summary to the user:

- Number of projects converted
- Number of packages centralized
- Any packages that were skipped or need manual attention
- Any `VersionOverride` entries that were added and why
- Any MSBuild properties that were kept or removed

Recommend the user run their test suite to verify no behavioral changes:

```bash
dotnet test
```

## Validation

- [ ] `Directory.Packages.props` exists with `ManagePackageVersionsCentrally` set to `true`
- [ ] Every in-scope `PackageReference` either has no `Version` attribute or uses `VersionOverride`
- [ ] Every referenced package has a corresponding `PackageVersion` entry in `Directory.Packages.props`
- [ ] `dotnet restore` completes without errors
- [ ] `dotnet build` completes without errors
- [ ] No orphaned version properties remain in build files (unless intentionally kept)

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| `NU1008` error after conversion | A `PackageReference` still has a `Version` attribute. Remove it or change to `VersionOverride` |
| `NU1010` error for missing package version | Add the missing `<PackageVersion>` entry to `Directory.Packages.props` |
| `NU1507` warning about multiple package sources | Configure [package source mapping](https://learn.microsoft.com/en-us/nuget/consume-packages/package-source-mapping) or use a single source |
| `Directory.Packages.props` not picked up | Ensure it is in the project directory or an ancestor directory. Only the closest one is evaluated |
| Multiple `Directory.Packages.props` files conflict | Use `Import` to chain files, or consolidate into one. Only the nearest file is evaluated per project |
| Version properties in `.props` files cause build errors | Decide whether to inline the version or keep the property in `Directory.Packages.props`. See [step 6](#step-6-handle-properties-that-defined-versions) |
| Conditional PackageReference loses its condition | Move the condition to the `PackageVersion` entry in `Directory.Packages.props`, or use `VersionOverride` in the project |
| `packages.config` projects are in scope | These must first be [migrated to PackageReference](https://learn.microsoft.com/en-us/nuget/consume-packages/migrate-packages-config-to-package-reference) before CPM conversion |
| Global tools or CLI tool references affected | `DotNetCliToolReference` items are deprecated and not managed by CPM. They can be ignored |

## More Info

See https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management for the full CPM documentation.
