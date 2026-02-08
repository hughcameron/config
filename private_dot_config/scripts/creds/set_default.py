#%%

import os
from pathlib import Path

import typer

import credutil

AWS_CREDENTIALS = Path(os.path.expanduser("~/.aws/credentials"))


#%%


accounts = credutil.get_creds(AWS_CREDENTIALS)

account_list = [a for a in accounts.keys() if a != "default"]


app = typer.Typer()


@app.command()
def set_default(account: str):
    if account not in account_list:
        typer.echo(
            f"Account '{account}' not found. Available accounts:\n{', '.join(account_list)}"
        )
        raise typer.Exit()
    typer.echo(f"Setting AWS account {account} as default.")
    accounts["default"] = accounts[account]
    with AWS_CREDENTIALS.open("w") as f:
        f.write(credutil.build_creds(accounts))


#%%


if __name__ == "__main__":
    app()
