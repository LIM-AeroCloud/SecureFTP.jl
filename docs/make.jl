using SFTP, Documenter, Changelog

# Generate a Documenter-friendly changelog from CHANGELOG.md
Changelog.generate(
    Changelog.Documenter(),
    joinpath(@__DIR__, "..", "CHANGELOG.md"),
    joinpath(@__DIR__, "src", "release-notes.md");
    repo = "LIM-AeroCloud/SFTP.jl",
)

# Build documentation
makedocs(
    modules=[SFTP],
    authors="Peter Bräuer <pb866.git@gmail.com> and contributors",
    sitename="Julia SFTP Documentation",
    format=Documenter.HTML(;
        canonical="https://LIM-AeroCloud.github.io/SFTP.jl",
        edit_link="dev",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Troubleshooting" => "troubleshooting.md",
        "Release notes" => "release-notes.md"
    ]
)

deploydocs(
    repo = "github.com/LIM-AeroCloud/SFTP.jl.git",
    devbranch="dev"
)
