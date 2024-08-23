module NonlinearSolveBase

using ArrayInterface: ArrayInterface
using Compat: @compat
using ConcreteStructs: @concrete
using FastClosures: @closure
using LinearAlgebra: norm
using Markdown: @doc_str
using RecursiveArrayTools: AbstractVectorOfArray, ArrayPartition
using SciMLBase: SciMLBase, ReturnCode, AbstractODEIntegrator
using StaticArraysCore: StaticArray

include("public.jl")
include("utils.jl")

include("common_defaults.jl")
include("termination_conditions.jl")
include("autodiff.jl")
include("immutable_problem.jl")

# Unexported Public API
@compat(public, (L2_NORM, Linf_NORM, NAN_CHECK, UNITLESS_ABS2, get_tolerance))

export RelTerminationMode, AbsTerminationMode, NormTerminationMode, RelNormTerminationMode,
       AbsNormTerminationMode, RelNormSafeTerminationMode, AbsNormSafeTerminationMode,
       RelNormSafeNormTerminationMode, AbsNormSafeNormTerminationMode

end
