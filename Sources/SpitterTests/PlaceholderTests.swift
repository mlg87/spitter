import SpitterCore

func runPlaceholderTests() {
    test("package builds and links SpitterCore") {
        expectEqual(Spitter.name, "Spitter")
    }
}
