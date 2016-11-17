#=
"""
```
mutation_RWMH(p0, l0, post0, tune,i, data; rvec = [], rval = [], px = [], lx = [], postx = [],m)
```

Execute one proposed move of the Metropolis-Hastings algorithm for a given parameter

### Arguments:
- `p0`: para(j,:)
        initial prior draw.
- `l0`: loglh(j)
        initial log-likelihood at the prior draw.
- `post0`: logpost(j)
           initial log-posterior at the prior draw.
- `tune`: the tune object, which is a struct/type object that contains information about tuning the SMC and the MH algorithms
- `i`: the index of the iteration of the SMC algorithm
- `data`: well-formed data as DataFrame
- `m`: model of type AbstractModel being estimated.

### Optional Arguments: 
- `rvec`: A matrix of horizontally concatenated random vectors ε as in Θ* = θ + ε for the proposed move in RWMH, for the purposes of testing that mutation_RWMH.
- `rval`: A vector of random values generated in MATLAB for the purposes of testing whether the proposed move exceeds the threshhold and is accepted (or rejected).
- `px`, `lx`, `postx`: Proposed new prior draw, log-likelihood, and log-posterior from executing the MATLAB code

### Output:

- `ind_para`: parasim(i,j,:) 
              Updated parameter vector
- `ind_loglh`: loglh(j)
               Updated log-likelihood
- `ind_post`: temp_acpt(j,1)
              Updated posterior
- `ind_acpt`: Indicator for acceptance or rejection (0 reject, 1 accept)

"""
=#
#change tune to be a sub-type of Tune or something in the future
#@debug
function mutation_RWMH(p0::Array{Float64,1}, l0::Float64, post0::Float64, tune, i::Int64, data::Matrix{Float64}, m::AbstractModel; rvec = [], rval = [], px = [], lx = [], postx = [])

if m.testing
    # If testing, set the random seeds at fixed numbers
    #srand(s.rng, 654)
    rvec = rvec
    rval = rval
else
    rvec = randn(tune.npara-length(tune.f_inds),1)
    rval = rand()

    #RW Proposal
    px_draw = p0 + squeeze(tune.c*chol(tune.R)'*rvec,2) #modify to be of the dimension of the original # of paras
    px_draw = reverse(px_draw)
    px = []
    for p in 1:length(m.parameters)
        if m.parameters[p].fixed == true
            append!(px,[m.parameters[p].value])
        else
            append!(px,[pop!(px_draw)])
        end
    end
    px = convert(Array{Float64},px)

    try
        out = posterior!(m,px,data;phi_smc=tune.phi[i])
        lx = out[:like]
        postx = out[:post] 
    catch
        #in the event that the proposed move is outside of the bounds
        lx = -Inf
        postx = -Inf
    end

    # Previous posterior needs to be updated (due to tempering)
    post0 = post0+(tune.phi[i]-tune.phi[i-1])*l0
end
    # Previous prior needs to have the fixed values reattached
    p0_pre = reverse(p0)
    p0 = []
    for p in 1:length(m.parameters)
        if m.parameters[p].fixed == true
            append!(p0,[m.parameters[p].value])
        else
            append!(p0,[pop!(p0_pre)])
        end
    end
    
# Accept/Reject
    alp = exp(postx - post0) # this is RW, so q is canceled out
    # println("alp: $(trunc(alp,4)) post0: $(trunc(post0,4)) l0:
    # $(trunc(l0,4)) postx: $(trunc(postx,4)) phi_factor:
    # $(trunc(tune.phi[i]-tune.phi[i-1],4))")
    # println("px: $px \n")


    open("output.txt","a") do x
        write(x,"alp: $(trunc(alp,4)) l0: $(trunc(l0,4)) post0: $(trunc(post0,4)) lx: $(trunc(lx,4)) postx: $(trunc(postx,4)) phi_factor: $(trunc(tune.phi[i]-tune.phi[i-1],4))\n")
        write(x,"px: $px \n")
        write(x,"p0: $p0 \n\n")
    end
    open("draws.csv","a") do x
        writecsv(x,reshape(px,(1,tune.npara)))
    end 
 
#@bp
rval = .5
if rval .< alp # accept
    ind_para   = px 
    ind_loglh  = lx
    ind_post   = postx
    ind_acpt   = 1
else
    ind_para   = p0
    ind_loglh  = l0
    ind_post   = post0
    ind_acpt   = 0
end

return ind_para, ind_loglh, ind_post, ind_acpt
end
