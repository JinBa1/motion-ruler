NVIM ?= nvim

.PHONY: test demo
test:
	$(NVIM) --headless -u NONE -i NONE -n -l tests/run.lua

demo:
	$(NVIM) -u examples/init.lua -i NONE -n
