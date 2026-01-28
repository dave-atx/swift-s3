import Testing
import ArgumentParser
@testable import ss3

@Test func defaultFlagsAreFalse() throws {
    let command = try ListCommand.parse([])
    #expect(command.long == false)
    #expect(command.human == false)
    #expect(command.time == false)
}

@Test func longFlagSetsLong() throws {
    let command = try ListCommand.parse(["-l"])
    #expect(command.long == true)
}

@Test func longFlagLongFormSetsLong() throws {
    let command = try ListCommand.parse(["--long"])
    #expect(command.long == true)
}

@Test func humanFlagSetsHuman() throws {
    let command = try ListCommand.parse(["-h"])
    #expect(command.human == true)
}

@Test func timeFlagSetsTime() throws {
    let command = try ListCommand.parse(["-t"])
    #expect(command.time == true)
}

@Test func timeFlagLongFormSetsTime() throws {
    let command = try ListCommand.parse(["--time"])
    #expect(command.time == true)
}

@Test func combinedFlagsLongAndTime() throws {
    let command = try ListCommand.parse(["-lt"])
    #expect(command.long == true)
    #expect(command.time == true)
}

@Test func separateFlagsWork() throws {
    let command = try ListCommand.parse(["-l", "-t"])
    #expect(command.long == true)
    #expect(command.time == true)
}

@Test func longAndHumanTogether() throws {
    let command = try ListCommand.parse(["-l", "-h"])
    #expect(command.long == true)
    #expect(command.human == true)
}

@Test func allThreeFlagsTogether() throws {
    let command = try ListCommand.parse(["-l", "-h", "-t"])
    #expect(command.long == true)
    #expect(command.human == true)
    #expect(command.time == true)
}
