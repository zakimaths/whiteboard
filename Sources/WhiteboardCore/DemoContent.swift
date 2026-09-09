import Foundation

/// Original, fictional examples that are safe to show in a public demonstration.
public enum DemoContent {
    @discardableResult public static func populate(_ library: Library, restore: Bool = false) throws -> URL {
        func text(_ value: String, _ x: Double, _ y: Double, _ size: Double = 22) -> BoardText {
            var item = BoardText(text:value,origin:Point(x,y)); item.size = size; return item
        }
        let existing = try library.list()
        var firstAdded: URL?
        func install(_ key: String, _ title: String, signature: String, _ make: () -> Board, finished: Bool = false) throws {
            let marker = library.root.appendingPathComponent(".demo-\(key)-v1")
            if !restore, FileManager.default.fileExists(atPath:marker.path) { return }
            let exact = existing.first(where: { $0.title == title })
            let recognised = !restore && existing.contains { item in
                if item.title == title { return true }
                return (try? library.load(item.url).texts.contains(where: { $0.text == signature })) ?? false
            }
            if !restore, recognised {
                // If creation succeeded but the initial status move failed, retry that
                // move before committing the marker. Renamed boards keep the user's status.
                if finished, let exact, exact.status != .finished { _ = try library.move(exact.url,to:.finished) }
                try Data("1\n".utf8).write(to:marker,options:.atomic)
                return
            }
            let created = try library.create(name:title,board:make())
            let result = finished ? try library.move(created,to:.finished) : created
            if firstAdded == nil { firstAdded = result }
            try Data("1\n".utf8).write(to:marker,options:.atomic)
        }
        var thought = Board(); thought.background = "paper"
        thought.texts = [text("An idea before it disappears.",250,240,36),text("A tiny shelf for the things I’m still figuring out.",250,310,24),text("CAPTURE",300,460,22),text("ADD A THOUGHT",670,460,22),text("KEEP IT",1180,460,22),text("No deadline. Just somewhere to pick it up again.",300,680,24)]
        for x in [500.0,980.0] {
            thought.ink.append(Ink(points:[Point(x,475),Point(x+110,475),Point(x+92,463),Point(x+110,475),Point(x+92,487)],colour:"blue",width:3))
        }
        try install("quick-thought","An idea before it disappears",signature:"A tiny shelf for the things I’m still figuring out.",{ thought })
        var done = Board(); done.background = "paper"
        done.texts = [text("Keep what worked.",280,280,40),text("Write → save → return when it’s useful.",280,360,25),text("Finished can always become unfinished again.",280,440,21)]
        try install("keep-what-worked","Keep what worked",signature:"Finished can always become unfinished again.",{ done },finished:true)
        var shapes = Board(); shapes.background = "paper"
        shapes.texts = [text("A thought, with a little more shape.",240,225,34),text("Sketch a line, arrow, box or circle with the pen.",240,290,21),text("Lift to tidy it. Undo restores your original ink.",240,330,19),text("CAPTURE",300,480,22),text("CONNECT",820,480,22),text("KEEP",1290,480,22),text("Try drawing below with Auto shapes on. No tool switching needed.",240,720,21),text("Hold Shift to keep a stroke freehand, or turn Auto shapes off.",240,765,19)]
        shapes.ink = [
            Ink(points:DrawingShape.rectangle.points(from:Point(240,430),to:Point(510,565)),colour:"blue"),
            Ink(points:DrawingShape.arrow.points(from:Point(550,495),to:Point(710,495)),colour:"ink"),
            Ink(points:DrawingShape.ellipse.points(from:Point(740,425),to:Point(1040,575)),colour:"red"),
            Ink(points:DrawingShape.arrow.points(from:Point(1080,495),to:Point(1200,495)),colour:"ink"),
            Ink(points:DrawingShape.rectangle.points(from:Point(1240,430),to:Point(1470,565)),colour:"green")
        ]
        try install("give-an-idea-shape","Give an idea some shape",signature:"Lift to tidy it. Undo restores your original ink.",{ shapes })
        if let firstAdded { return firstAdded }
        let remaining = try library.list()
        return remaining.first?.url ?? library.root
    }
}
