using NonlinearSolve

f(u, p) = u .* u .- 2
u0 = [1.0, 1.0]
probN = NonlinearProblem(f, u0)
@time solver = solve(probN, abstol = 1e-9)
@time solver = solve(probN, RobustMultiNewton(), abstol = 1e-9)
@time solver = solve(probN, FastShortcutNonlinearPolyalg(), abstol = 1e-9)

# https://github.com/SciML/NonlinearSolve.jl/issues/153

function f(du, u, p)
    s1, s1s2, s2 = u
    k1, c1, Δt = p

    du[1] = -0.25 * c1 * k1 * s1 * s2
    du[2] = 0.25 * c1 * k1 * s1 * s2
    du[3] = -0.25 * c1 * k1 * s1 * s2
end

prob = NonlinearProblem(f, [2.0,2.0,2.0], [1.0, 2.0, 2.5])
sol = solve(prob)