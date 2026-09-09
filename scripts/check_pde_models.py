"""Independent numerical checks of the closed-form examples; Python standard library only.
This checks the mathematics, not a PDE solver inside Whiteboard or a LaTeX parser.
"""
import math

pi = math.pi

def close(a, b, tol=1e-6):
    assert abs(a-b) <= tol * max(1, abs(a), abs(b)), (a, b)

def integrate(f, end=1.0, n=2000):
    h = end/n
    return h * (0.5*(f(0)+f(end))+sum(f(i*h) for i in range(1,n)))

kappa, length, amplitude = 0.3, 1.7, 1.2

def heat(x, t):
    return amplitude * sum(b*math.exp(-kappa*(n*pi/length)**2*t)*math.sin(n*pi*x/length) for n,b in [(1,1),(3,0.35)])

def heat_dx(x,t):
    return amplitude * sum(b*(n*pi/length)*math.exp(-kappa*(n*pi/length)**2*t)*math.cos(n*pi*x/length) for n,b in [(1,1),(3,0.35)])

for t in [0.03,0.04,0.2]:
    close(heat(0,t),0); close(heat(length,t),0)
    for fraction in [0.17,0.36,0.71]:
        x, h, dt = length*fraction, 1e-4, 1e-5
        ut = (heat(x,t+dt)-heat(x,t-dt))/(2*dt)
        uxx = (heat(x+h,t)-2*heat(x,t)+heat(x-h,t))/h**2
        close(ut,kappa*uxx,2e-6)
for x in [0.13,0.8,1.3]:
    close(heat(x,0),amplitude*(math.sin(pi*x/length)+0.35*math.sin(3*pi*x/length)))
t,dt=0.1,1e-5
energy=lambda t:0.5*integrate(lambda x:heat(x,t)**2,length)
close((energy(t+dt)-energy(t-dt))/(2*dt),-kappa*integrate(lambda x:heat_dx(x,t)**2,length),2e-6)
print('PASS heat PDE residual, initial/boundary values and L2 energy identity')

speed=1.3
wave=lambda x,t:amplitude*math.cos(pi*speed*t/length)*math.sin(pi*x/length)
wave_dt=lambda x,t:-amplitude*pi*speed/length*math.sin(pi*speed*t/length)*math.sin(pi*x/length)
wave_dx=lambda x,t:amplitude*pi/length*math.cos(pi*speed*t/length)*math.cos(pi*x/length)
for t in [0.03,0.17,0.61]:
    close(wave(0,t),0); close(wave(length,t),0)
    for fraction in [0.17,0.36,0.71]:
        x,h=length*fraction,1e-4
        utt=(wave(x,t+h)-2*wave(x,t)+wave(x,t-h))/h**2
        uxx=(wave(x+h,t)-2*wave(x,t)+wave(x-h,t))/h**2
        close(utt,speed**2*uxx,2e-6)
    e=0.5*integrate(lambda x:wave_dt(x,t)**2+speed**2*wave_dx(x,t)**2,length)
    close(e,amplitude**2*speed**2*pi**2/(4*length))
close(wave_dt(0.37,0),0)
print('PASS wave PDE residual, fixed ends, initial velocity and conserved energy')

poisson=lambda x,y:math.sin(pi*x)*math.sin(pi*y)
for z in [0.13,0.5,0.83]:
    for x,y in [(0,z),(1,z),(z,0),(z,1)]: close(poisson(x,y),0)
close(poisson(0.5,0.5),1)
truncation_errors=[]
for n in [8,16,32]:
    h=1/n
    truncation_errors.append(max(abs((4*poisson(i*h,j*h)-poisson((i-1)*h,j*h)-poisson((i+1)*h,j*h)-poisson(i*h,(j-1)*h)-poisson(i*h,(j+1)*h))/h**2-2*pi**2*poisson(i*h,j*h)) for i in range(1,n) for j in range(1,n)))
assert all(3.9 < a/b < 4.1 for a,b in zip(truncation_errors,truncation_errors[1:])), truncation_errors

def poisson_grid_error(n):
    """Solve the interior five-point system with conjugate gradients."""
    h, side = 1/n, n-1
    def apply(values):
        result=[0.0]*(side*side)
        for j in range(side):
            for i in range(side):
                k=j*side+i
                neighbours=(values[k-1] if i else 0.0)+(values[k+1] if i+1<side else 0.0)
                neighbours+=(values[k-side] if j else 0.0)+(values[k+side] if j+1<side else 0.0)
                result[k]=(4*values[k]-neighbours)/h**2
        return result
    rhs=[2*pi**2*poisson((i+1)*h,(j+1)*h) for j in range(side) for i in range(side)]
    solution=[0.0]*len(rhs); residual=rhs[:]; direction=residual[:]
    rr=sum(value*value for value in residual)
    for _ in range(4*len(rhs)):
        product=apply(direction)
        alpha=rr/sum(a*b for a,b in zip(direction,product))
        solution=[u+alpha*p for u,p in zip(solution,direction)]
        residual=[r-alpha*a for r,a in zip(residual,product)]
        next_rr=sum(value*value for value in residual)
        if next_rr < 1e-24: break
        beta=next_rr/rr; direction=[r+beta*p for r,p in zip(residual,direction)]; rr=next_rr
    return max(abs(solution[j*side+i]-poisson((i+1)*h,(j+1)*h)) for j in range(side) for i in range(side))

solution_errors=[poisson_grid_error(n) for n in [8,16,32]]
assert all(3.8 < a/b < 4.2 for a,b in zip(solution_errors,solution_errors[1:])), solution_errors
close(2*pi**2*integrate(lambda x:math.sin(pi*x)**2)**2,pi**2/2)
print('PASS Poisson boundary values, energy, second-order truncation and solved-grid convergence')
