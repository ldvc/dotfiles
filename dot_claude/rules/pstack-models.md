# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Task `model`). Alias entries in a panel list still count toward its fan-out.
# budget: unlimited (max)
feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: opus max
hardest tasks: opus max
how explorer: inherit-parent
how explainer: opus max
why investigators: inherit-parent
why synthesizer: opus max
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: opus max
arena runners: opus max, inherit-parent
arena cross-judge pool: opus max, inherit-parent
swarm workers: inherit-parent
architect runners: opus max, inherit-parent
interrogate reviewers: opus max, inherit-parent
