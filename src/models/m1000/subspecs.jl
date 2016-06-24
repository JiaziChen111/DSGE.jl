"""
`init_subspec!(m::Model1000)`

Initializes a model subspecification by overwriting parameters from
the original model object with new parameter objects. This function is
called from within the model constructor.
"""
function init_subspec!(m::Model1000)
    if subspec(m) == "ss2"
        return
    elseif subspec(m) == "ss5"
        return ss5!(m)
    else
        error("This subspec is not defined.")
    end
end

"""
`ss5(m::Model1000)`

Initializes subspecification 5 for Model1000. Specifically, fixes ι_w
and ι_p to 0 (so that intermediate goods producers who do not readjust
prices and wages in a given period do not index to inflation.)
"""
function ss5!(m::Model1000)

    m <= parameter(:ι_p, 0.0, fixed=true,
                   description= "ι_p: The persistence of last period's inflation in
                   the equation that describes the intertemporal
                   change in prices for intermediate goods producers
                   who cannot adjust prices. The change in prices is a
                   geometric average of steady-state inflation
                   (π_star, with weight (1-ι_p)) and last period's
                   inflation (π_{t-1})).",
                   tex_label="\\iota_p")


    m <= parameter(:ι_w,   0.0, fixed=true,
                   description="ι_w: No description available.",
                   tex_label="\\iota_w")
end
