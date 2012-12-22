
all:
	tclsh8.5 tclmk/make.tcl

test:
	./build/seri-bin/seri --haskellf \
		--include seri/sri \
		--main-is main \
		-f seri/sri/Seri/SMT/Tests/Sudoku2.sri > foo.hs
	HOME=build/home ghc -fno-warn-overlapping-patterns \
		-fno-warn-missing-fields \
		-main-is __main \
		-prof -auto-all -rtsopts \
		-o foo foo.hs
	./foo +RTS -p -K1g

testio:
	./build/seri-bin/seri --desugar \
		--include seri/sri \
		--main-is Seri.SMT.Tests.Share.main \
		-f seri/sri/Seri/SMT/Tests/Share.sri +RTS -p -K1g

clean:
	rm -rf build/seri-smt build/seri build/seri-bin build/test


