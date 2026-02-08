
# Create a mamba environment from a yml definition (vcr = enVironmnent CReate)
export def vcr [env_name] {
    ^mamba env create -y -f $"/Users/hugh/github/hughcameron/mambas/($env_name).yml"
}

# Update a mamba environment from a yml definition (vup = enVironmnent UP)
export def vup [env_name] {
    ^mamba env update -f $"/Users/hugh/github/hughcameron/mambas/($env_name).yml"
}

# Delete a named mamba environment (vrm = enVironmnent RM)
export def vrm [env_name] {
    ^mamba env remove -y -n $env_name
}

# Rebuild a named mamba environment (vrb = enVironmnent ReBuild)
export def vrb [env_name] {
    ^mamba env remove -y -n $env_name
    ^mamba env create -y -f $"/Users/hugh/github/hughcameron/mambas/($env_name).yml"
    conda activate $env_name
    # mamba install ipykernel
    # python -m ipykernel install --user --name $env_name --display-name $"Python ($env_name)"
}
