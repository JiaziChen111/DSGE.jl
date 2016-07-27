<<<<<<< HEAD
function mutation_RWMH(p0, l0, post0, tune, i, f)
# RWMH for mutation step
# INPUT
# tune
# p0 = para(j,:)'
# l0 = loglh(j)
# post0 = logpost(j)

# OUTPUT
# ind_para
# ind_loglh
# ind_post
# ind_acpt


# RW proposal
px = p0 + tune.c*chol(tune.R)'*randn(tune.npara,1)
[postx, lx] = f(px, tune.phi(i))
=======
"""
```
mutation_RWMH(p0, l0, post0, tune,i, data; rvec = [], rval = [], px = [], lx = [], postx = [])
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

#change tune to be a sub-type of Tune or something in the future
function mutation_RWMH(p0::Array{Float64,1}, l0::Float64, post0::Float64, tune, i::Int64, df::DataFrame, m::AbstractModel; rvec = [], rval = [], px = [], lx = [], postx = [])

if m.testing
    # If testing, set the random seeds at fixed numbers
    #srand(s.rng, 654)
    rvec = rvec
    rval = rval
else
    rvec = randn(tune.npara,1)
    rval = rand()
end

data = df_to_matrix(m,df)

#RW Proposal
px = p0 + tune.c*chol(tune.R)'*rvec
lx = likelihood(m,data)
postx = posterior(m,data;phi_smc=tune.phi(i))[:post] #check if this is correct?
>>>>>>> b5a1226eaa4230332682137a28754cd25b88dea6

# Previous posterior needs to be updated (due to tempering)
post0 = post0+(tune.phi(i)-tune.phi(i-1))*l0

# Accept/Reject
alp = exp(postx - post0) # this is RW, so q is canceled out
<<<<<<< HEAD
if rand < alp # accept
=======
    
if rval .< alp # accept
>>>>>>> b5a1226eaa4230332682137a28754cd25b88dea6
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

<<<<<<< HEAD
# # outside of function
# parasim(i,j,:) = ind_para
# loglh(j)       = ind_loglh
# temp_acpt(j,1) = ind_acpt
=======
>>>>>>> b5a1226eaa4230332682137a28754cd25b88dea6
return ind_para, ind_loglh, ind_post, ind_acpt
end
