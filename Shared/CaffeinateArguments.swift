enum CaffeinateArguments {
    static func forHelper(pid: Int32) -> [String] {
        ["-d", "-i", "-m", "-s", "-w", String(pid)]
    }
}
