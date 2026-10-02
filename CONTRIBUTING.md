# Contributing to OpenGolf Tycoon

Thank you for considering contributing!

## Getting Started

1. Install [Godot Engine 4.6+](https://godotengine.org/download) (standard version, not .NET)
2. Fork and clone the repository
3. Open `project.godot` in Godot
4. Press F5 to run

No setup scripts or build steps required - all assets are included.

## How to Contribute

### Reporting Bugs
- Use a clear title
- Describe steps to reproduce
- Include Godot version and OS

### Code Contributions

Areas needing help:
- **Core Systems**: Golfer AI, shot physics, economy
- **Art**: Isometric terrain tiles, buildings, golfers
- **Audio**: Music and sound effects
- **Documentation**: Tutorials, wiki

### Style Guide

Follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
- snake_case for variables/functions
- PascalCase for classes
- SCREAMING_SNAKE_CASE for constants
- Always use type hints

### Testing

Unit tests use GUT. From the project root:

```bash
make test
# or
./test.sh
```

On a clean checkout this extracts the bundled Godot 4.6 Linux build (or uses `$GODOT` / a `godot` on `PATH`) and imports the project once, then runs `tests/unit/`. Re-runs skip that setup.

### Pull Request Process

1. Create a feature branch
2. Make your changes
3. Run `make test` and confirm the suite passes
4. Submit a PR with clear description

## License

By contributing, you agree that your contributions will be licensed under MIT.
