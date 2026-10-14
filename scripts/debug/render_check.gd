class_name RenderCheck
extends RefCounted
## Runtime check for a GPU driver bug seen with the Forward+ (Ultra) renderer
## on Mali-G77 / driver r32p1: as soon as a frame renders any 3D, every render
## target reads back with each 8-pixel-row strip duplicated from the one above.
## The Ultra build checks one frame at the main menu and, if the pattern is
## found, tells the player to use the standard (Mobile renderer) build.


## Detects the corruption seen on Mali: each strip of N pixel rows (8 at full
## resolution on a Mali-G77) is an exact copy of the strip above it. Returns the
## fraction of non-flat strips that repeat, best over strip sizes and
## alignments. Validated offline: corrupted captures score 1.0, clean ~0.004.
static func row_block_duplication(img: Image) -> float:
	var g := img.duplicate() as Image
	if g.get_format() != Image.FORMAT_L8:
		g.convert(Image.FORMAT_RGBA8)
		g.convert(Image.FORMAT_L8)
	var w := g.get_width()
	var h := g.get_height()
	var d := g.get_data()
	var best := 0.0
	for blk in [4, 8]:
		for phase in range(0, 2 * blk, 2):
			var informative := 0
			var matches := 0
			var y: int = phase
			while y + 2 * blk <= h:
				for x in range(0, w, 11):
					var flat := true
					var same := true
					var v0 := d[y * w + x]
					for i in blk:
						var px := d[(y + i) * w + x]
						if absi(px - v0) > 6:
							flat = false
						if absi(px - d[(y + blk + i) * w + x]) > 2:
							same = false
					if not flat:
						informative += 1
						if same:
							matches += 1
				y += 2 * blk
			if informative > 50:
				best = maxf(best, float(matches) / informative)
	return best
