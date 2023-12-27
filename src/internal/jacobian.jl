abstract type AbstractNonlinearSolveJacobianCache{iip} <: Function end

SciMLBase.isinplace(::AbstractNonlinearSolveJacobianCache{iip}) where {iip} = iip

@concrete mutable struct JacobianCache{iip} <: AbstractNonlinearSolveJacobianCache{iip}
    J
    f
    uf
    fu
    u
    p
    jac_cache
    alg
    njacs::Int
end

# TODO: Cache for Non-Square Case
function JacobianCache(prob, alg, f::F, u, p) where {F}
    iip = isinplace(prob)
    uf = JacobianWrapper{iip}(f, p)

    haslinsolve = __hasfield(alg, Val(:linsolve))

    has_analytic_jac = SciMLBase.has_jac(f)
    linsolve_needs_jac = haslinsolve && __needs_concrete_A(alg.linsolve)
    alg_wants_jac = __concrete_jac(alg) !== nothing && __concrete_jac(alg)
    needs_jac = linsolve_needs_jac || alg_wants_jac

    fu = f.resid_prototype === nothing ? (iip ? zero(u) : f(u, p)) :
         (iip ? deepcopy(f.resid_prototype) : f.resid_prototype)

    if !has_analytic_jac && needs_jac
        sd = __sparsity_detection_alg(f, alg.ad)
        ad = alg.ad
        jac_cache = iip ? sparse_jacobian_cache(ad, sd, uf, fu, u) :
                    sparse_jacobian_cache(ad, sd, uf, __maybe_mutable(u, ad); fx = fu)
    else
        jac_cache = nothing
    end

    J = if !needs_jac
        if SciMLBase.has_jvp(f)
            # JacVec(uf, u; fu, autodiff = __get_nonsparse_ad(alg.ad))
        else
            # if iip
            #     jvp = (_, u, v) -> (du_ = similar(fu); f.jvp(du_, v, u, p); du_)
            #     jvp! = (du_, _, u, v) -> f.jvp(du_, v, u, p)
            # else
            #     jvp = (_, u, v) -> f.jvp(v, u, p)
            #     jvp! = (du_, _, u, v) -> (du_ .= f.jvp(v, u, p))
            # end
            # op = SparseDiffTools.FwdModeAutoDiffVecProd(f, u, (), jvp, jvp!)
            # FunctionOperator(op, u, fu; isinplace = Val(true), outofplace = Val(false),
            #     p, islinear = true)
        end
        error("Not Yet Implemented!")
    else
        if has_analytic_jac
            f.jac_prototype === nothing ? undefmatrix(u) : f.jac_prototype
        elseif f.jac_prototype === nothing
            init_jacobian(jac_cache; preserve_immutable = Val(true))
        else
            f.jac_prototype
        end
    end

    return JacobianCache{iip}(J, f, uf, fu, u, p, jac_cache, alg, 0)
end

function JacobianCache(prob, alg, f::F, u::Number, p) where {F}
    uf = JacobianWrapper{false}(f, p)
    return JacobianCache{false}(u, f, uf, u, u, p, nothing, alg, 0)
end

@inline (cache::JacobianCache)() = cache(cache.J, cache.u, cache.p)
# Default Case is a NoOp: Operators and Such
@inline (cache::JacobianCache)(J, u, p) = J
# Scalar
function (cache::JacobianCache)(::Number, u, p)
    cache.njacs += 1
    return last(value_derivative(cache.uf, u))
end
# Compute the Jacobian
function (cache::JacobianCache{iip})(J::Union{AbstractMatrix, Nothing}, u, p) where {iip}
    cache.njacs += 1
    if iip
        if has_jac(cache.f)
            cache.f.jac(J, u, p)
        else
            sparse_jacobian!(J, cache.alg.ad, cache.jac_cache, cache.uf, cache.fu, u)
        end
    else
        if has_jac(cache.f)
            return cache.f.jac(u, p)
        elseif can_setindex(typeof(J))
            return sparse_jacobian!(J, cache.alg.ad, cache.jac_cache, cache.uf, u)
        else
            return sparse_jacobian(cache.alg.ad, cache.jac_cache, cache.uf, u)
        end
    end
    return J
end

# Sparsity Detection Choices
@inline __sparsity_detection_alg(_, _) = NoSparsityDetection()
@inline function __sparsity_detection_alg(f::NonlinearFunction, ad::AbstractSparseADType)
    if f.sparsity === nothing
        if f.jac_prototype === nothing
            if is_extension_loaded(Val(:Symbolics))
                return SymbolicsSparsityDetection()
            else
                return ApproximateJacobianSparsity()
            end
        else
            jac_prototype = f.jac_prototype
        end
    elseif f.sparsity isa AbstractSparsityDetection
        if f.jac_prototype === nothing
            return f.sparsity
        else
            jac_prototype = f.jac_prototype
        end
    elseif f.sparsity isa AbstractMatrix
        jac_prototype = f.sparsity
    elseif f.jac_prototype isa AbstractMatrix
        jac_prototype = f.jac_prototype
    else
        error("`sparsity::typeof($(typeof(f.sparsity)))` & \
               `jac_prototype::typeof($(typeof(f.jac_prototype)))` is not supported. \
               Use `sparsity::AbstractMatrix` or `sparsity::AbstractSparsityDetection` or \
               set to `nothing`. `jac_prototype` can be set to `nothing` or an \
               `AbstractMatrix`.")
    end

    if SciMLBase.has_colorvec(f)
        return PrecomputedJacobianColorvec(; jac_prototype, f.colorvec,
            partition_by_rows = ad isa ADTypes.AbstractSparseReverseMode)
    else
        return JacPrototypeSparsityDetection(; jac_prototype)
    end
end

@inline function __value_derivative(f::F, x::R) where {F, R}
    T = typeof(ForwardDiff.Tag(f, R))
    out = f(ForwardDiff.Dual{T}(x, one(x)))
    return ForwardDiff.value(out), ForwardDiff.extract_derivative(T, out)
end
