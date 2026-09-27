"""Bounded full-tile benchmark plus V2 correctness checks; no default hardware."""
from .smoke import main


if __name__ == "__main__":
    import sys
    raise SystemExit(main(["--extended", *sys.argv[1:]]))
