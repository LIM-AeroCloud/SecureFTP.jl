using SecureFTP, Documenter, Changelog

# Generate a Documenter-friendly changelog from CHANGELOG.md
Changelog.generate(
    Changelog.Documenter(),
    joinpath(@__DIR__, "..", "CHANGELOG.md"),
    joinpath(@__DIR__, "src", "release-notes.md");
    repo = "LIM-AeroCloud/SecureFTP.jl",
)

# Build documentation
makedocs(
    modules=[SecureFTP],
    authors="Peter Bräuer <pb866.git@gmail.com> and contributors",
    sitename="SecureFTP.jl Documentation",
    checkdocs=:public,
    format=Documenter.HTML(;
        canonical="https://LIM-AeroCloud.github.io/SecureFTP.jl",
        edit_link="dev",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Server" => "server.md",
        "Filesystem" => "filesystem.md",
        "Troubleshooting" => "troubleshooting.md",
        "Release notes" => "release-notes.md",
        "Index" => "register.md"
    ]
)

deploydocs(
    repo = "github.com/LIM-AeroCloud/SecureFTP.jl.git",
    devbranch="dev"
)
