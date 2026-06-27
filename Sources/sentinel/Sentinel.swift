import ArgumentParser

@main
struct Sentinel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sentinel",
        abstract: "Archive integrity monitor — detect bit rot and silent deletions.",
        subcommands: [
            BaselineCommand.self,
            VerifyCommand.self,
        ]
    )
}
