"""Minimal builder for Excalidraw scenes (.excalidraw JSON).

Usage:
    import sys; sys.path.insert(0, "<directory containing exdraw.py>")
    from exdraw import Diagram, C
    d = Diagram(scale=1.0)
    vpc = d.rect(0, 0, 300, 200, stroke=C.green, label="VPC", label_pos="top-left")
    d.table(10, 220, ["Destination", "Next Hop"], [["0.0.0.0/0", "TGW"]])
    d.save("out.excalidraw")

All coordinates/sizes passed in are multiplied by `scale`, so you can lay out a
diagram in the pixel coordinates of a reference image and enlarge it at the end.
Font sizes are NOT scaled.
"""
import json
import random
import string
import time


class C:
    """Palette (AWS-ish + Excalidraw defaults)."""
    black = "#1e1e1e"
    gray = "#5f6368"
    lightgray = "#d0d0d0"
    white = "#ffffff"
    transparent = "transparent"
    green = "#3f8624"          # VPC border
    green_bg = "#e9f3e6"       # public/private subnet fill
    blue = "#147eba"           # subnet label
    blue_bg = "#e6f2f8"
    purple = "#8c4fff"         # networking icons
    purple_dark = "#5a30b5"
    orange = "#ed7100"         # compute
    red = "#dd344c"
    salmon = "#f19e91"
    lightblue = "#9cc3e6"
    header_gray = "#6b6b6b"
    header_red = "#f28b82"
    header_blue = "#5dadec"


FONT = {"hand": 5, "normal": 2, "code": 3}  # Excalifont, Helvetica, Cascadia
LINE_HEIGHT = 1.25
CHAR_W = 0.56  # average glyph width / fontSize for Helvetica (approx.)


def _id(n=20):
    return "".join(random.choices(string.ascii_letters + string.digits, k=n))


def text_size(text, font_size):
    lines = text.split("\n")
    w = max(len(l) for l in lines) * font_size * CHAR_W
    h = len(lines) * font_size * LINE_HEIGHT
    return w, h


class Diagram:
    def __init__(self, scale=1.0, font="normal", roughness=0):
        self.s = scale
        self.font = FONT[font]
        self.roughness = roughness
        self.elements = []

    # ---------- low level ----------
    def _base(self, type_, x, y, w, h, stroke, bg, stroke_width=1,
              style="solid", rounded=False, opacity=100):
        el = {
            "id": _id(), "type": type_,
            "x": x, "y": y, "width": w, "height": h, "angle": 0,
            "strokeColor": stroke, "backgroundColor": bg,
            "fillStyle": "solid", "strokeWidth": stroke_width,
            "strokeStyle": style, "roughness": self.roughness,
            "opacity": opacity, "groupIds": [], "frameId": None,
            "roundness": {"type": 3} if rounded else None,
            "seed": random.randint(1, 2**31), "version": 1,
            "versionNonce": random.randint(1, 2**31), "isDeleted": False,
            "boundElements": [], "updated": int(time.time() * 1000),
            "link": None, "locked": False,
        }
        self.elements.append(el)
        return el

    def _text_el(self, x, y, text, size, color, align, valign, container=None,
                 w=None, h=None):
        tw, th = text_size(text, size)
        el = self._base("text", x, y, w or tw, h or th, color, C.transparent)
        el.update({
            "text": text, "originalText": text, "fontSize": size,
            "fontFamily": self.font, "textAlign": align,
            "verticalAlign": valign, "containerId": container,
            "autoResize": True, "lineHeight": LINE_HEIGHT,
        })
        return el

    # ---------- shapes ----------
    def text(self, x, y, text, size=16, color=C.black, align="left",
             anchor="top-left"):
        """Free text. anchor: top-left | center | top-center."""
        x, y = x * self.s, y * self.s
        tw, th = text_size(text, size)
        if anchor == "center":
            x, y = x - tw / 2, y - th / 2
        elif anchor == "top-center":
            x = x - tw / 2
        return self._text_el(x, y, text, size, color, align, "top")["id"]

    def _shape(self, type_, x, y, w, h, stroke, bg, stroke_width, style,
               rounded, label, label_pos, size, label_color, opacity=100):
        x, y, w, h = x * self.s, y * self.s, w * self.s, h * self.s
        el = self._base(type_, x, y, w, h, stroke, bg, stroke_width, style,
                        rounded, opacity)
        if label:
            if label_pos == "center":
                # bound text: Excalidraw keeps it centered inside the shape
                t = self._text_el(x, y, label, size, label_color, "center",
                                  "middle", container=el["id"])
                tw, th = text_size(label, size)
                t["x"], t["y"] = x + (w - tw) / 2, y + (h - th) / 2
                el["boundElements"].append({"type": "text", "id": t["id"]})
            else:
                pad = 8
                tw, th = text_size(label, size)
                pos = {
                    "top-left": (x + pad, y + pad, "left"),
                    "top-center": (x + (w - tw) / 2, y + pad, "center"),
                    "below": (x + (w - tw) / 2, y + h + 4, "center"),
                    "above": (x + (w - tw) / 2, y - th - 4, "center"),
                }[label_pos]
                self._text_el(pos[0], pos[1], label, size, label_color,
                              pos[2], "top")
        return el["id"]

    def rect(self, x, y, w, h, stroke=C.black, bg=C.transparent,
             stroke_width=1, style="solid", rounded=False, label=None,
             label_pos="center", size=16, label_color=None, opacity=100):
        """label_pos: center (bound) | top-left | top-center | below | above."""
        return self._shape("rectangle", x, y, w, h, stroke, bg, stroke_width,
                           style, rounded, label, label_pos, size,
                           label_color or stroke, opacity)

    def ellipse(self, x, y, w, h, stroke=C.black, bg=C.transparent,
                stroke_width=1, style="solid", label=None, label_pos="center",
                size=16, label_color=None, opacity=100):
        return self._shape("ellipse", x, y, w, h, stroke, bg, stroke_width,
                           style, False, label, label_pos, size,
                           label_color or stroke, opacity)

    def _linear(self, type_, pts, stroke, stroke_width, style, start_head,
                end_head):
        pts = [(px * self.s, py * self.s) for px, py in pts]
        x0, y0 = pts[0]
        rel = [[px - x0, py - y0] for px, py in pts]
        xs, ys = [p[0] for p in rel], [p[1] for p in rel]
        el = self._base(type_, x0, y0, max(xs) - min(xs), max(ys) - min(ys),
                        stroke, C.transparent, stroke_width, style)
        el.update({"points": rel, "lastCommittedPoint": None,
                   "startBinding": None, "endBinding": None,
                   "startArrowhead": start_head, "endArrowhead": end_head})
        if type_ == "arrow":
            el["elbowed"] = False
        return el["id"]

    def line(self, *pts, stroke=C.black, stroke_width=1, style="solid"):
        return self._linear("line", pts, stroke, stroke_width, style, None, None)

    def arrow(self, *pts, stroke=C.black, stroke_width=1, style="solid",
              start_head=None, end_head="arrow"):
        return self._linear("arrow", pts, stroke, stroke_width, style,
                            start_head, end_head)

    # ---------- composites ----------
    def table(self, x, y, headers, rows, col_widths=None, row_h=22,
              header_bg=C.header_gray, header_color=C.white, size=12,
              stroke=C.lightgray, title=None, title_size=13):
        """Route-table style grid. Coordinates are pre-scale. Returns bbox."""
        n = len(headers)
        col_widths = col_widths or [70] * n
        cy = y
        if title:
            self.text(x, y, title, size=title_size)
            cy += title_size * LINE_HEIGHT / self.s + 4
        all_rows = [headers] + rows
        for r, row in enumerate(all_rows):
            lines = max(str(c).count("\n") + 1 for c in row)
            h = max(row_h, (lines * size * LINE_HEIGHT + 6) / self.s)
            cx = x
            for c, cell in enumerate(row):
                head = r == 0
                self.rect(cx, cy, col_widths[c], h, stroke=stroke,
                          bg=header_bg if head else C.white, label=str(cell),
                          size=size,
                          label_color=header_color if head else C.black)
                cx += col_widths[c]
            cy += h
        return (x, y, sum(col_widths), cy - y)

    def note(self, x, y, w, h, text, size=12, stroke=C.gray):
        """Dashed rounded box with left-aligned text (annotation)."""
        self.rect(x, y, w, h, stroke=stroke, bg=C.white, style="dashed",
                  rounded=True)
        self.text(x + 5, y + 4, text, size=size)

    def group(self, *ids):
        gid = _id()
        for el in self.elements:
            if el["id"] in ids or el.get("containerId") in ids:
                el["groupIds"].append(gid)
        return gid

    # ---------- output ----------
    def scene(self):
        return {
            "type": "excalidraw", "version": 2,
            "source": "https://excalidraw.com",
            "elements": self.elements,
            "appState": {"viewBackgroundColor": "#ffffff", "gridSize": None},
            "files": {},
        }

    def save(self, path):
        with open(path, "w") as f:
            json.dump(self.scene(), f, indent=1)
        return path
