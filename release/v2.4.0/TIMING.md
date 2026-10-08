# Selected Timing evidence

| Engine | ALM | LAB | M10K | Worst setup | Timing/reproduction |
|---|---:|---:|---:|---:|---|
| A A1+A2 |23,503|3,705|85|+0.088ns|All4corner constrained checks/TNS0; independent rebuild NOT_RUN |
| B seed3 |31,787|3,995|84|+0.467ns|All4corner checks/TNS0; two independent matching Full Compilations/RBF |
| C stable | retained | retained | retained | not newly signed off | Legacy accepted artifact; original producing build not recovered |
| D |22,074|3,700|79|+0.495ns|All4corner constrained checks/TNS0; independent rebuild NOT_RUN |

For A/B/D the five recorded checks per corner are setup, hold, recovery, removal and pulse width. Corners are Slow/Fast 1100mV at 100°C / -40°C. Original detailed corner values and limits are referenced by adoption-manifest.json and repository validation/. Flow Successful alone is insufficient. A's old da862ee core-88.815ns/HDMI-0.188ns audit is retained as resolved-by-new-selection, not waived or overwritten.

Inherited I/O/unmatched-filter limits remain. D explicitly records 3 unconstrained inputs / 50 outputs. No new exception or SDC relaxation occurred. ALM percentage alone does not describe LAB headroom, packing/routing or Timing margin. B 3995/4191 LAB leaves 196; A 3705 leaves 486. This integration reruns no Quartus compilation.
