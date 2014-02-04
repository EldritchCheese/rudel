all: compile

compile:
	emacs -batch -q -no-site-file -eval '(setq compile-rudel-directory t)' -load rudel-compile.el

rudel-loaddefs.el: rudel-compile.el
	emacs -batch -q -no-site-file -load $<

clean:
	rm -f *.elc rudel-loaddefs.el

.PHONY: all compile clean