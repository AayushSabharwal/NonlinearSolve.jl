struct DFSane{T, F} <: AbstractNonlinearSolveAlgorithm
    σₘᵢₙ::T
    σₘₐₓ::T
    σ₁::T
    M::Int
    γ::T
    τₘᵢₙ::T
    τₘₐₓ::T
    nₑₓₚ::Int
    ηₛ::F
    max_inner_iterations::Int
end

function DFSane(;
                σₘᵢₙ = 1.0f-10,
                σₘₐₓ = 1.0f+10,
                σ₁ = 1.0f0,
                M = 10,
                γ = 1.0f-4,
                τₘᵢₙ = 0.1f0,
                τₘₐₓ = 0.5f0,
                nₑₓₚ = 2,
                ηₛ = (f₍ₙₒᵣₘ₎₁, n, xₙ, fₙ) -> f₍ₙₒᵣₘ₎₁ / n^2,
                max_inner_iterations = 1000)
    return DFSane{typeof(σₘᵢₙ), typeof(ηₛ)}(σₘᵢₙ, # Typeof thing?
                                            σₘₐₓ,
                                            σ₁,
                                            M,
                                            γ,
                                            τₘᵢₙ,
                                            τₘₐₓ,
                                            nₑₓₚ,
                                            ηₛ,
                                            max_inner_iterations)
end
mutable struct DFSaneCache{iip, fType, ffType, algType, uType, resType, T, ηₛType, pType,
                           INType,
                           tolType,
                           probType}
    f::fType
    ff::ffType
    alg::algType
    uₙ::uType
    uₙ₋₁::uType
    fuₙ::resType
    fuₙ₋₁::resType
    𝒹::uType
    ℋ::uType
    f₍ₙₒᵣₘ₎ₙ::T
    f₍ₙₒᵣₘ₎ₙ₋₁::T
    f̄::T
    M::Int
    σₙ::T
    σₘᵢₙ::T
    σₘₐₓ::T
    α₁::T
    α₋::T
    α₊::T
    η::T
    γ::T
    τₘᵢₙ::T
    τₘₐₓ::T
    ηₛ::ηₛType
    p::pType
    force_stop::Bool
    maxiters::Int
    internalnorm::INType
    retcode::SciMLBase.ReturnCode.T
    abstol::tolType
    prob::probType
    stats::NLStats
    function DFSaneCache{iip}(f::fType, ff::ffType, alg::algType, uₙ::uType, uₙ₋₁::uType,
                              fuₙ::resType, fuₙ₋₁::resType, 𝒹::uType, ℋ::uType, f₍ₙₒᵣₘ₎ₙ::T,
                              f₍ₙₒᵣₘ₎ₙ₋₁::T, f̄::T, M::Int, σₙ::T, σₘᵢₙ::T, σₘₐₓ::T, α₁::T,
                              α₋::T,
                              α₊::T, η::T, γ::T, τₘᵢₙ::T, τₘₐₓ::T, ηₛ::ηₛType, p::pType,
                              force_stop::Bool,
                              maxiters::Int,
                              internalnorm::INType, retcode::SciMLBase.ReturnCode.T,
                              abstol::tolType, prob::probType,
                              stats::NLStats) where {iip, fType, ffType, algType, uType,
                                                     resType, T, ηₛType, pType, INType,
                                                     tolType,
                                                     probType
                                                     }
        new{iip, fType, ffType, algType, uType, resType, T, ηₛType, pType, INType, tolType,
            probType
            }(f, ff, alg, uₙ, uₙ₋₁, fuₙ, fuₙ₋₁, 𝒹, ℋ, f₍ₙₒᵣₘ₎ₙ, f₍ₙₒᵣₘ₎ₙ₋₁, f̄, M, σₙ,
              σₘᵢₙ, σₘₐₓ, α₁, α₋, α₊, η, γ, τₘᵢₙ,
              τₘₐₓ, ηₛ, p, force_stop, maxiters, internalnorm,
              retcode,
              abstol, prob, stats)
    end
end

function SciMLBase.__init(prob::NonlinearProblem{uType, iip}, alg::DFSane,
                          args...;
                          alias_u0 = false,
                          maxiters = 1000,
                          abstol = 1e-6,
                          internalnorm = DEFAULT_NORM,
                          kwargs...) where {uType, iip}
    if alias_u0
        uₙ = prob.u0
    else
        uₙ = deepcopy(prob.u0)
    end
    p = prob.p

    T = eltype(uₙ)

    σₘᵢₙ, σₘₐₓ, γ, τₘᵢₙ, τₘₐₓ = T(alg.σₘᵢₙ), T(alg.σₘₐₓ), T(alg.γ), T(alg.τₘᵢₙ), T(alg.τₘₐₓ)
    α₁ = one(T)
    α₊, α₋ = α₁, α₁
    η = α₁
    γ = T(alg.γ)
    f₍ₙₒᵣₘ₎ₙ₋₁, f₍ₙₒᵣₘ₎ₙ = α₁, α₁
    σₙ = T(alg.σ₁)
    M = alg.M
    nₑₓₚ = alg.nₑₓₚ
    𝒹, uₙ₋₁, fuₙ, fuₙ₋₁ = copy(uₙ), copy(uₙ), copy(uₙ), copy(uₙ)

    if iip
        f(dx, x) = prob.f(dx, x, p)
        function ff(fₓ, x)
            f(fₓ, x)
            fₙₒᵣₘ = sum(abs2, fₓ)
            fₙₒᵣₘ ^= (nₑₓₚ / 2)
            return fₙₒᵣₘ
        end
        f₍ₙₒᵣₘ₎ₙ₋₁ = ff(fuₙ₋₁, uₙ₋₁)
    else
        f(x) = prob.f(x, p)
        function ff!(x)
            fₓ = f(x)
            sum!(abs2, fₙₒᵣₘ, fₓ)
            fₙₒᵣₘ ^= (nₑₓₚ / 2)
            return fₓ, fₙₒᵣₘ
        end
        fuₙ₋₁, f₍ₙₒᵣₘ₎ₙ₋₁ = ff(uₙ₋₁)
    end

    ℋ = fill(f₍ₙₒᵣₘ₎ₙ₋₁, M)
    f̄ = f₍ₙₒᵣₘ₎ₙ₋₁
    ηₛ = (n, xₙ, fₙ) -> alg.ηₛ(f₍ₙₒᵣₘ₎ₙ₋₁, n, xₙ, fₙ)

    return DFSaneCache{iip}(f, ff, alg, uₙ, uₙ₋₁, fuₙ, fuₙ₋₁, 𝒹, ℋ, f₍ₙₒᵣₘ₎ₙ, f₍ₙₒᵣₘ₎ₙ₋₁,
                            f̄, M, σₙ, σₘᵢₙ, σₘₐₓ, α₁, α₋, α₊, η, γ, τₘᵢₙ,
                            τₘₐₓ, ηₛ, p, false, maxiters,
                            internalnorm, ReturnCode.Default, abstol, prob,
                            NLStats(1, 0, 0, 0, 0)) # What should NL stats be?
end

function perform_step!(cache::DFSaneCache{true})
    if isdefined(Main, :Infiltrator)
        Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    end
    @unpack ff, alg, uₙ, uₙ₋₁, fuₙ, fuₙ₋₁, 𝒹, ℋ, f₍ₙₒᵣₘ₎ₙ, f₍ₙₒᵣₘ₎ₙ₋₁,
    f̄, σₙ, σₘᵢₙ, σₘₐₓ, α₁, α₋, α₊, η, γ, ηₛ, τₘᵢₙ, τₘₐₓ, M = cache

    T = eltype(uₙ)
    cache.stats.nsteps += 1
    n = cache.stats.nsteps
    # Spectral parameter range check
    σₙ = sign(σₙ) * clamp(abs(σₙ), σₘᵢₙ, σₘₐₓ)

    # Line search direction
    @. 𝒹 = -σₙ * fuₙ₋₁

    η = ηₛ(n, uₙ₋₁, fuₙ₋₁)

    f̄ = maximum(ℋ)
    α₊ = α₁
    α₋ = α₁
    @. uₙ = uₙ₋₁ + α₊ * 𝒹

    f₍ₙₒᵣₘ₎ₙ = ff(fuₙ, uₙ)

    for _ in 1:(cache.max_inner_iterations)
        𝒸 = f̄ + η - γ * α₊^2 * f₍ₙₒᵣₘ₎ₙ₋₁

        (f₍ₙₒᵣₘ₎ₙ .≤ 𝒸) && break

        α₊ = clamp(α₊^2 * f₍ₙₒᵣₘ₎ₙ₋₁ /
                   (f₍ₙₒᵣₘ₎ₙ + (T(2) * α₊ - T(1)) * f₍ₙₒᵣₘ₎ₙ₋₁),
                   τₘᵢₙ * α₊,
                   τₘₐₓ * α₊)  
        @. uₙ = uₙ₋₁ + α₊ * 𝒹 # correct order?

        f₍ₙₒᵣₘ₎ₙ = ff(fuₙ, uₙ)

        (f₍ₙₒᵣₘ₎ₙ .≤ 𝒸) && break

        α₋ = clamp(α₋^2 * f₍ₙₒᵣₘ₎ₙ₋₁ / (f₍ₙₒᵣₘ₎ₙ + (T(2) * α₋ - T(1)) * f₍ₙₒᵣₘ₎ₙ₋₁),
                      τₘᵢₙ * α₋,
                      τₘₐₓ * α₋)  
        @. uₙ = uₙ₋₁ - α₋ * 𝒹 # correct order?
        f₍ₙₒᵣₘ₎ₙ = ff(fuₙ, uₙ)
    end

    if cache.internalnorm(cache.fuₙ) < cache.abstol
        cache.force_stop = true
    end

    # Update spectral parameter
    @. uₙ₋₁ = uₙ - uₙ₋₁
    @. fuₙ₋₁ = fuₙ - fuₙ₋₁

    α₊ = sum(abs2, uₙ₋₁)
    α₋ = sum(uₙ₋₁ .* fuₙ₋₁)
    σₙ = α₊ / (α₋ + T(1e-5))

    # Take step
    @. uₙ₋₁ = uₙ
    @. fuₙ₋₁ = fuₙ
    f₍ₙₒᵣₘ₎ₙ₋₁ = f₍ₙₒᵣₘ₎ₙ

    # Update history
    ℋ[n % M + 1] = f₍ₙₒᵣₘ₎ₙ
    cache.stats.nf += 1
    @pack! cache = f₍ₙₒᵣₘ₎ₙ₋₁, σₙ
    return nothing
end

function SciMLBase.solve!(cache::DFSaneCache)
    while !cache.force_stop && cache.stats.nsteps < cache.maxiters
        perform_step!(cache)
        cache.stats.nsteps += 1
    end

    if cache.stats.nsteps == cache.maxiters
        cache.retcode = ReturnCode.MaxIters
    else
        cache.retcode = ReturnCode.Success
    end

    SciMLBase.build_solution(cache.prob, cache.alg, cache.u, cache.fu;
                             retcode = cache.retcode, stats = cache.stats)
end
