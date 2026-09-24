GODOT ?= godot
GDTOOLKIT = uv tool run --from gdtoolkit==4.5.0
RUFF = uv tool run --from ruff==0.16.8 ruff
PY_SOURCES = $(sort $(wildcard tools/check_*.py) tools/build_devmode_art.py tools/build_area_art.py tools/build_industrial_hazards.py tools/build_new_enemy_art.py tools/gen_audio.py tools/run_godot_check.py)

.PHONY: run dev perf-overlay benchmark-cave import format format-check lint docs test f1-check check
run:
	$(GODOT) --path .

dev:
	$(GODOT) --path . -- --dev-mode

perf-overlay:
	$(GODOT) --path . -- --dev-mode --perf-overlay

benchmark-cave:
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; $(GODOT) --path . --windowed --resolution 1920x1080 --audio-driver Dummy --disable-vsync --max-fps 0 res://tools/benchmark_cave_runtime.tscn -- --dev-mode --test-mode --test-save-root=$$tmp --benchmark-cave

import:
	$(GODOT) --headless --path . --editor --import --quit

format:
	$(GDTOOLKIT) gdformat scripts tools/*.gd
	$(RUFF) format $(PY_SOURCES)

format-check:
	$(GDTOOLKIT) gdformat --check scripts tools/*.gd
	$(RUFF) format --check $(PY_SOURCES)

lint:
	$(GDTOOLKIT) gdlint scripts tools/*.gd
	$(RUFF) check $(PY_SOURCES)

docs:
	python3 tools/check_docs.py

# Regression suites are registered in one list: SUITES in tools/run_godot_check.py.
# Run a subset while iterating: python3 tools/run_godot_check.py walljump combat
test: import
	python3 tools/run_godot_check.py

f1-check: test

check: import docs format-check lint
	python3 tools/run_godot_check.py
	git diff --check
