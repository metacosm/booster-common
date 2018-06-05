## Developing scripts to be used by `for-all-boosters.sh`

The scripts in this directory are meant to be invoked via `for-all-boosters.sh`
for.

Their purpose is to change the pom in ad-hoc ways that do not make sense being part
of the main `for-all-boosters.sh` script. 

An example invocation is:

```bash
./for-all-boosters.sh -fb master-no-parent script "$(pwd)/playground/pom/add-dependency-management.sh"
```

The existing scripts use a mix of tools to accomplish their tasks: `xq`, `sed`, `perl`

### Caution

Developing these scripts is not very easy since working with XML is difficult.
Also the scripts need to be tested with various boosters since the structure of the POM
is not standardized meaning that various find and replace procedures might work on some
boosters and not others

For more advanced use cases, scripts in Python or Groovy could be developed.
This would however necessitate changing the `script` command of `for-all-boosters.sh` 