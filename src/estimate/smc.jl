"""
```
smc(m,data)
```

### Arguments:

- `m`: A model object, from which its parameters values, prior dists, and bounds will be referenced
- `data`: A matrix containing time series of the observables to be used in the calculation of the posterior/likelihood

### Keyword Arguments:
- `verbose`: The desired frequency of function progress messages printed to standard out.
	- `:none`: No status updates will be reported.
	- `:low`: Status updates for SMC initialization and recursion will be included.
	    - `:high`: Status updates for every iteration of SMC is output, which includes the mu and sigma of each individual parameter draw after each iteration, as well as the calculated acceptance rate, the ESS, and the number of times resampled.

### Outputs

- `mu`: The mean of a particular parameter as calculated by taking the weighted sum of that parameter from the particle draws made in that particular stage Nφ. 
- `sig`: The standard deviation of a particular parameter. 

### Overview

Sequential Monte Carlo can be used in lieu of Random Walk Metropolis Hastings to generate parameter samples from high-dimensional parameter spaces using sequentially constructed proposal densities.  

SMC is broken up into three main steps:

- `Correction`: Reweight the particles from stage n-1 by defining "incremental weights", incweight, which gradually incorporate the likelihood function p(Y|θ(i,n-1)) into the particle weights. 
- `Selection`: Resample the particles if the distribution of particles begins to degenerate, according to a tolerance level ESS < N/2. The current resampling technique employed is systematic resampling. 

- `Mutation`: Propagate particles {θ(i),W(n)} via N(MH) steps of a Metropolis Hastings algorithm.  
"""
function smc(m::AbstractModel, data::Matrix; verbose::Symbol=:low)
    #--------------------------------------------------------------
    #Set Parameters of Algorithm
    #--------------------------------------------------------------
    
    n_Φ = get_setting(m, :n_Φ)
    n_part = get_setting(m, :n_particles)
    n_params = n_parameters(m)
    n_blocks = get_setting(m, :n_smc_blocks)

    fixed_para_inds = find([ θ.fixed for θ in m.parameters])
    free_para_inds  = find([!θ.fixed for θ in m.parameters])
    c = get_setting(m, :c)
    accept = get_setting(m, :init_accept)
    target = get_setting(m, :target_accept)

    parallel = get_setting(m, :use_parallel_workers)

    # Creating the tempering schedule
    λ = get_setting(m, :λ)
    tempering_schedule = ((collect(1:1:n_Φ)-1)/(n_Φ-1)).^λ

    #Matrices for storing

    para_sim = zeros(n_Φ, n_part, n_params) # parameter draws
    weight_sim = zeros(n_part, n_Φ) # weights
    zhat = zeros(n_Φ, 1) # normalization constant
    nresamp = 0 # record # of iteration resampled

    c_sim = zeros(n_Φ,1) # scale parameter
    ESS_sim = zeros(n_Φ,1) # ESS
    accept_sim = zeros(n_Φ,1) # average acceptance rate
    rsmp_sim = zeros(n_Φ,1) # 1 if resampled

    #--------------------------------------------------------------
    #Initialize Algorithm: Draws from prior
    #--------------------------------------------------------------

    if VERBOSITY[verbose] >= VERBOSITY[:low]
	println("\n\n SMC starts ....  \n\n  ")
    end

    # Particle draws from the parameter's marginal priors
    prior_sim = zeros(n_part,n_params)

    # Posterior values at prior draws
    loglh = zeros(n_part, 1)
    logpost = zeros(n_part, 1)

    # fix seed if testing
    if m.testing
        println("seed set")
        srand(42)
    end

    i = 1
    while i <= n_part
        try
            T = typeof(m.parameters[1].value)
            priodraw = Array{T}(n_params)

            #Parameter draws per particle
            for j in 1:n_params

                priodraw[j] = if !m.parameters[j].fixed            
                    prio = rand(m.parameters[j].prior.value)
                    
                    # Resample until all prior draws are within the value bounds
                    while !(m.parameters[j].valuebounds[1] < prio < m.parameters[j].valuebounds[2])
                        prio = rand(m.parameters[j].prior.value)
                    end
                    
                    prio
                else
                    m.parameters[j].value
                end
            end
            prior_sim[i,:] = priodraw'
            out = posterior!(m, convert(Array{Float64,1},priodraw), data; φ_smc = tempering_schedule[1])
            logpost[i] = out[:post]
            loglh[i] = out[:like]
            i += 1
        end
    end

    para_sim[1,:,:] = prior_sim # Draws from prior 
    weight_sim[:,1] = 1/n_part 
    zhat[1] = sum(weight_sim[:,1]) 

    i = 1
    para = squeeze(para_sim[i, :, :],1);
    weight = repmat(weight_sim[:, i], 1, n_params);
    
    if m.testing
        open("draws.csv","a") do x
            writecsv(x,reshape(para_sim[i,:,:],(n_part,n_parameters(m))))
        end 
    end
     
    μ  = sum(para.*weight,1);
    σ = sum((para - repmat(μ, n_part, 1)).^2 .*weight,1);
    σ = (sqrt(σ));
    
        
    if VERBOSITY[verbose] >= VERBOSITY[:low]
	println("--------------------------")
        println("Iteration = $(i) / $(n_Φ)")
	println("--------------------------")
        println("phi = $(tempering_schedule[i])")
	println("--------------------------")
        println("c = $(c)")
	println("--------------------------")
        if VERBOSITY[verbose] >= VERBOSITY[:high]
            for n=1:n_params
                println("$(m.parameters[n].key) = $(μ[n]), $(σ[n])")
	    end
        end
    end


    #RECURSION

    if VERBOSITY[verbose] >= VERBOSITY[:low]
	println("\n\n SMC Recursion starts \n\n")
    end

    for i=2:n_Φ
	#------------------------------------
	# (a) Correction
	#------------------------------------
	# Incremental weights
	incweight = exp((tempering_schedule[i] - tempering_schedule[i-1]) * loglh)

	# Update weights
	weight_sim[:,i] = weight_sim[:,i-1].*incweight 
        zhat[i] = sum(weight_sim[:,i]) 

	# Normalize weights
	weight_sim[:, i] = weight_sim[:, i]/zhat[i]
	#------------------------------------
	# (b) Selection 
	#------------------------------------

	ESS = 1/sum(weight_sim[:,i].^2)
        if isnan(ESS)
            writecsv("loglh.csv",loglh)
            writecsv("wtsim.csv",weight_sim)
            println("incweight: $incweight")
            println("zhat: $(zhat[i])")
            println("weights: $(weight_sim[:,i-1].*incweight)")
            error("ESS is NaN")
        end
	if (ESS < n_part/2)
	    id = systematic_resampling(m, weight_sim[:,i])
            para_sim[i-1, :, :] = para_sim[i-1, id, :]
	    loglh = loglh[id]
	    logpost = logpost[id]
	    weight_sim[:,i] = 1/n_part
	    nresamp += 1
	    rsmp_sim[i] = 1
	end

	#------------------------------------
	# (c) Mutation
	#------------------------------------

        c = c*(0.95 + 0.10*exp(16*(accept - target))/(1 + exp(16*(accept - target))))
        
        para = squeeze(para_sim[i-1, :, :][:,:,free_para_inds],1)
        weight = repmat(weight_sim[:,i], 1, n_params)[:,free_para_inds]
        μ = sum(para.*weight,1)
	z =  (para - repmat(μ, n_part, 1))
        R_temp = (z.*weight)'*z
        R = (R_temp + R_temp')/2 # one can also use nearestSPD(R_temp) 

	temp_accept = zeros(n_part, 1) # Initialize acceptance indicator
        
        if parallel
            out = @sync @parallel (hcat) for j = 1:n_part 
                mutation_RWMH(m, data, vec(para[j,:]'), loglh[j], logpost[j], i, R, tempering_schedule)
            end
        else
            out = [mutation_RWMH(m, data, vec(para[j,:]'), loglh[j], logpost[j], i, R, tempering_schedule)  for j = 1:n_part]
        end

        para_sim_temp = Array{Float64}[out[i][1] for i=1:length(out)]
        fillmat = zeros(length(para_sim_temp), length(para_sim_temp[1]))
        for j = 1:length(para_sim_temp)
            fillmat[j,:] = para_sim_temp[j]
        end
        para_sim[i,:,:] = fillmat
        loglh = Float64[out[i][2] for i=1:length(out)]
        logpost = Float64[out[i][3] for i=1:length(out)]
        temp_accept = Int[out[i][4] for i=1:length(out)]
        
        accept = mean(temp_accept) # update average acceptance rate
        c_sim[i,:]    = c; # scale parameter
        ESS_sim[i,:]  = ESS; # ESS
        accept_sim[i,:] = accept; # average acceptance rate
        
        para = squeeze(para_sim[i, :, :],1);
        weight = repmat(weight_sim[:, i], 1, n_params);
        
        μ  = sum(para.*weight,1);
        σ = sum((para - repmat(μ, n_part, 1)).^2 .*weight,1);
        σ = (sqrt(σ));
        
        if VERBOSITY[verbose] >= VERBOSITY[:low]
	    println("--------------------------")
            println("Iteration = $(i) / $(n_Φ)")
	    println("--------------------------")
            println("phi = $(tempering_schedule[i])")
	    println("--------------------------")
            println("c = $(c)")
            println("accept = $(accept)")
            println("ESS = $(ESS)   ($(nresamp) total resamples.)")
	    println("--------------------------")
            if VERBOSITY[verbose] >= VERBOSITY[:high]
                for n=1:n_params
                    println("$(m.parameters[n].key) = $(μ[n]), $(σ[n])")
	        end
            end
        end
        
        
    end
    if m.testing
        open("wtsim.csv","a") do x
            writecsv(x,weight_sim)
        end
    end
    #------------------------------------
    # Saving parameter draws
    #------------------------------------
    if !m.testing
        save_file = h5open(rawpath(m,"estimate","mhsave.h5"),"w")
        n_saved_obs = n_part
        n_chunks = max(floor(n_saved_obs/5000),1)
        para_save = d_create(save_file, "mhparams", datatype(Float32),
                             dataspace(n_saved_obs,n_params),
                             "chunk", (n_chunks,n_params))
        post_save = d_create(save_file, "mhposterior", datatype(Float32),
                             dataspace(n_saved_obs,1),
                             "chunk", (n_chunks,1))
        TTT_save  = d_create(save_file, "mhTTT", datatype(Float32),
                             dataspace(n_saved_obs,n_states_augmented(m),n_states_augmented(m)),
                             "chunk", (n_chunks,n_states_augmented(m),n_states_augmented(m)))
        RRR_save  = d_create(save_file, "mhRRR", datatype(Float32),
                             dataspace(n_saved_obs,n_states_augmented(m),n_shocks_exogenous(m)),
                             "chunk", (n_chunks,n_states_augmented(m),n_shocks_exogenous(m)))
        zend_save = d_create(save_file, "mhzend", datatype(Float32),
                             dataspace(n_saved_obs,n_states_augmented(m)),
                             "chunk", (n_chunks,n_states_augmented(m)))
        
        if parallel
            out = @sync @parallel (hcat) for j = 1:n_part 
                posterior!(m, vec(para[j,:]'), data, sampler=true)
            end
        else
            out = [posterior!(m, vec(para[j,:]'), data, sampler=true)  for j = 1:n_part]
        end
        
        for i = 1:n_part
            para_save[i,:]  = map(Float32,para[i,:])
            post_save[i,:]  = map(Float32,out[i][:post])
            TTT_save[i,:,:] = map(Float32,out[i][:mats][:TTT])
            RRR_save[i,:,:] = map(Float32,out[i][:mats][:RRR])
            zend_save[i,:]  = map(Float32,out[i][:mats][:zend]')
        end
        close(save_file)
    end
        
end
