import Foundation

/// Original, fictional examples that are safe to show in a public demonstration.
public enum DemoContent {
    @discardableResult public static func populate(_ library: Library) throws -> URL {
        func text(_ value: String, _ x: Double, _ y: Double, _ size: Double = 22) -> BoardText {
            var item = BoardText(text:value,origin:Point(x,y)); item.size = size; return item
        }
        let url = try PDEExamples.installMissing(library).first ?? library.list().first?.url
        var thought = Board(); thought.background = "paper"
        thought.texts = [text("An idea before it disappears.",250,240,36),text("A tiny shelf for the things I’m still figuring out.",250,310,24),text("CAPTURE",300,460,22),text("ADD A THOUGHT",670,460,22),text("KEEP IT",1180,460,22),text("No deadline. Just somewhere to pick it up again.",300,680,24)]
        for x in [500.0,980.0] {
            thought.ink.append(Ink(points:[Point(x,475),Point(x+110,475),Point(x+92,463),Point(x+110,475),Point(x+92,487)],colour:"blue",width:3))
        }
        let thoughtURL = try library.create(name:"An idea before it disappears",board:thought)
        var done = Board(); done.background = "paper"
        done.texts = [text("Keep what worked.",280,280,40),text("Write → save → return when it’s useful.",280,360,25),text("Finished can always become unfinished again.",280,440,21)]
        let finished = try library.create(name:"Keep what worked",board:done); _ = try library.move(finished,to:.finished)
        var shapes = Board(); shapes.background = "paper"
        shapes.texts = [text("A thought, with a little more shape.",240,225,34),text("Sketch a line, arrow, box or circle with the pen.",240,290,21),text("Lift to tidy it. Undo restores your original ink.",240,330,19),text("CAPTURE",300,480,22),text("CONNECT",820,480,22),text("KEEP",1290,480,22),text("Try drawing below with Auto shapes on. No tool switching needed.",240,720,21),text("Hold Shift to keep a stroke freehand, or turn Auto shapes off.",240,765,19)]
        shapes.ink = [
            Ink(points:DrawingShape.rectangle.points(from:Point(240,430),to:Point(510,565)),colour:"blue"),
            Ink(points:DrawingShape.arrow.points(from:Point(550,495),to:Point(710,495)),colour:"ink"),
            Ink(points:DrawingShape.ellipse.points(from:Point(740,425),to:Point(1040,575)),colour:"red"),
            Ink(points:DrawingShape.arrow.points(from:Point(1080,495),to:Point(1200,495)),colour:"ink"),
            Ink(points:DrawingShape.rectangle.points(from:Point(1240,430),to:Point(1470,565)),colour:"green")
        ]
        _ = try library.create(name:"Give an idea some shape",board:shapes)
        return url ?? thoughtURL
    }
}
