from enum import Enum

class ModeColors(Enum):
    NONE = 0
    PER_LED = 1
    MODE_SPECIFIC = 2
    RANDOM = 3

class RGBColor:
    def __init__(self, red, green, blue):
        self.red, self.green, self.blue = red, green, blue
    def __repr__(self):
        return "RGBColor(%d,%d,%d)" % (self.red, self.green, self.blue)
    def __eq__(self, o):
        return (self.red, self.green, self.blue) == (o.red, o.green, o.blue)
