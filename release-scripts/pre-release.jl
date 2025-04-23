using Dates

# Parse main Project.toml
project = joinpath(@__DIR__, "..", "Project.toml")
lines = readlines(project)
# Find Julia version
vstring = "version = "
i = findfirst(startswith(vstring), lines)
vstart, vend = findall(isequal('"'), lines[i])
vstart += 1
vend -= 1
println("current version: ", lines[i][vstart:vend])
version = VersionNumber(lines[i][vstart:vend])

# Set stable version
if !isempty(version.prerelease)
    println("Drop prerelease version ", join(version.prerelease, "."))
end
if !isempty(version.build)
    println("Drop build version ", join(version.build, "."))
end
version = string(VersionNumber(version.major, version.minor, version.patch))
lines[i] = vstring * '"' * version * '"'
println("set version to ", version)

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end

# Update Changelog
changelog = joinpath(@__DIR__, "..", "CHANGELOG.md")
lines = readlines(changelog)
# Update WIP to new version
i = findfirst(isequal("## [unreleased]"), lowercase.(lines))
if isnothing(i)
    throw(ArgumentError("No unreleased version found in changelog"))
else
    lines[i] = "## [v$version] - $(Dates.today())"
    open(changelog, "w+") do io
        println.(io, lines)
    end
end
