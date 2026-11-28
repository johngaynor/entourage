# entourage asks every repo for a `setup` recipe that makes a fresh checkout
# ready to work in ("What a repo provides" in herdr/README.md). This repo has
# nothing to install: its tests need only bash and the machine's own git,
# sqlite3 and jq. So setup writes nothing, which also makes it safe to run
# twice. Anything a new worktree comes to need goes here.
setup:
    @echo "entourage: nothing to install"
