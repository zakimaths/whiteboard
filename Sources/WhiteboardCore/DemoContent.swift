import Foundation

/// Original, fictional examples that are safe to show in a public demonstration.
public enum DemoContent {
    @discardableResult public static func populate(_ library: Library) throws -> URL {
        func text(_ value: String, _ x: Double, _ y: Double, _ size: Double = 22) -> BoardText {
            var item = BoardText(text:value,origin:Point(x,y)); item.size = size; return item
        }
        let url = try library.create(name:"One question, two attempts")
        var prompt = Board(); prompt.background = "paper"
        prompt.texts = [text("PRACTICE PROMPT · SAMPLE CONTENT",30,20,14),text("A curve, a tangent, a little working space.",30,65,24),text("For y = x², find the tangent at x = 2.",30,112,21),text("Sketch your reasoning before checking the result.",30,160,17)]
        let imageData = try BoardRenderer.png(prompt,package:url)
        let asset = try library.importAsset(data:imageData,extension:"png",to:url)
        var board = Board(); board.background = "paper"
        board.texts = [text("A little room to figure it out.",240,225,36),text("Keep the question. Make room for your thinking.",240,280,19),text("01  /  THE QUESTION",240,350,15),text("02  /  MY WORKING",990,350,15),text("y = x²",1020,425,28),text("dy/dx = 2x  →  slope = 4",1020,480,25),text("y − 4 = 4(x − 2)",1020,540,25),text("y = 4x − 4",1020,600,30),text("A fresh attempt is one duplicate away.",240,865,20)]
        let reference = BoardImage(asset:asset,frame:Rect(240,385,650,245)); board.images = [reference]
        board.ink = [Ink(points:[Point(280,540),Point(615,540)],colour:"blue",width:4,imageID:reference.id),Ink(points:[Point(1020,650),Point(1325,650)],colour:"green",width:5),Ink(points:[Point(300,815),Point(300,665)],width:2),Ink(points:[Point(270,785),Point(650,785)],width:2)]
        let curve = (0...60).map { i -> Point in let x = Double(i)/60; return Point(315+x*240,785-x*x*100) }
        board.ink.append(Ink(points:curve,colour:"blue",width:3))
        try library.save(board,at:url)
        var thought = Board(); thought.background = "paper"
        thought.texts = [text("An idea before it disappears.",250,240,36),text("A tiny shelf for the things I’m still figuring out.",250,310,24),text("CAPTURE",300,460,22),text("ADD A THOUGHT",670,460,22),text("KEEP IT",1180,460,22),text("No deadline. Just somewhere to pick it up again.",300,680,24)]
        for x in [500.0,980.0] {
            thought.ink.append(Ink(points:[Point(x,475),Point(x+110,475),Point(x+92,463),Point(x+110,475),Point(x+92,487)],colour:"blue",width:3))
        }
        _ = try library.create(name:"An idea before it disappears",board:thought)
        var done = Board(); done.background = "paper"
        done.texts = [text("Keep what worked.",280,280,40),text("Write → save → return when it’s useful.",280,360,25),text("Finished can always become unfinished again.",280,440,21)]
        let finished = try library.create(name:"Keep what worked",board:done); _ = try library.move(finished,to:.finished)
        return url
    }
}
