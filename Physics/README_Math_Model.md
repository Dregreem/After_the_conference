# Mathematical Model of DC Motor Servo Plant
## Theoretical Foundations & Implementation

**Document Version:** 1.0  
**Author:** Control Systems Analysis  
**Purpose:** Thesis-level documentation of servo dynamics model  
**Scope:** 2nd-order nonlinear plant with static/dynamic friction and mechanical constraints

---

## Table of Contents
1. [System Overview](#system-overview)
2. [State-Space Representation](#state-space-representation)
3. [Nonlinear Friction Dynamics](#nonlinear-friction-dynamics)
4. [Equation of Motion](#equation-of-motion)
5. [Hard Mechanical Limits](#hard-mechanical-limits)
6. [Energy Accounting](#energy-accounting)
7. [Implementation Notes](#implementation-notes)

---

## System Overview

The servo plant is modeled as a **2nd-order nonlinear system** with the following characteristics:

- **Plant Input:** Normalized control signal $u(t) \in [-1, +1]$ (dimensionless duty cycle)
- **Plant Outputs:** Angular position $\theta(t)$ and angular velocity $\dot{\theta}(t)$
- **Nonlinearity:** Stick-slip friction (stiction) with distinct static and kinetic regimes
- **Constraints:** Hard mechanical angle limits (soft-stop enforcement via velocity zeroing)
- **Auxiliary Output:** Cumulative control effort (energy proxy)

### Physical Interpretation

The system models a rotational actuator (e.g., stepper motor, servo motor) subject to:
- Motor torque generation proportional to control signal
- Static friction preventing motion below a threshold
- Kinetic friction opposing motion when sliding
- Viscous damping (velocity-dependent resistance)
- Mechanical hard stops at angle extrema

---

## State-Space Representation

### State Vector

$$\mathbf{x}(t) = \begin{bmatrix} \theta(t) \\ \dot{\theta}(t) \\ E(t) \end{bmatrix} \in \mathbb{R}^3$$

where:
- $\theta(t)$: Angular position (radians)
- $\dot{\theta}(t)$: Angular velocity (rad/s)
- $E(t)$: Cumulative control effort (dimensionless energy proxy)

### Input & Parameter Vector

$$u(t) \in [-1, +1] \quad \text{(control signal)}$$

$$\boldsymbol{\theta}_p = \{J, T_{\max}, T_s, T_d, c, \omega_d\} \quad \text{(parameters)}$$

where:
- $J$: Moment of inertia (kg⋅m²)
- $T_{\max}$: Maximum motor torque (N⋅m)
- $T_s$: Static friction threshold (N⋅m)
- $T_d$: Dynamic (kinetic) friction torque (N⋅m)
- $c$: Viscous damping coefficient (N⋅m⋅s/rad)
- $\omega_d$: Velocity deadband for stiction transition (rad/s)

---

## Nonlinear Friction Dynamics

### Physical Motivation

Traditional models assume constant viscous friction proportional to velocity. However, real servos exhibit **stiction** (static friction), where:

1. At rest ($|\dot{\theta}| < \omega_d$): Motor must generate torque exceeding $T_s$ to initiate motion
2. While sliding ($|\dot{\theta}| \geq \omega_d$): A constant (or near-constant) kinetic friction $T_d$ opposes motion
3. Transition between regimes is discontinuous, creating a stick-slip nonlinearity

### Stiction Model (Dead-Zone with Hysteresis)

The friction torque $T_f$ is defined piecewise:

$$T_f(\dot{\theta}, T_m) = \begin{cases}
T_m & \text{if } |\dot{\theta}| < \omega_d \text{ and } |T_m| \leq T_s \\
\text{sgn}(T_m) \cdot T_d & \text{if } |\dot{\theta}| < \omega_d \text{ and } |T_m| > T_s \\
-\text{sgn}(\dot{\theta}) \cdot T_d & \text{if } |\dot{\theta}| \geq \omega_d
\end{cases}$$

where:
- $T_m = u(t) \cdot T_{\max}$ is the motor torque command
- $\text{sgn}(\cdot)$ is the signum function
- The first case (stiction region): friction exactly balances motor torque → zero acceleration

### Interpretation

**Case 1 — Static Equilibrium (Stiction Active):**  
When velocity is negligible and motor torque is below the stiction threshold, the motor remains locked. The friction torque passively equals the motor torque, preventing motion:
$$T_f = T_m \quad \Rightarrow \quad \ddot{\theta} = 0$$

**Case 2 — Breaking Stiction:**  
When motor torque exceeds static friction, the motor overcomes stiction and enters sliding mode. Friction switches to kinetic.

**Case 3 — Kinetic Friction (Sliding):**  
Once moving, kinetic friction $T_d$ (typically less than $T_s$) opposes motion. The direction of friction always opposes velocity direction.

### Mathematical Advantages

This model:
- ✓ Captures stick-slip oscillations at low speeds
- ✓ Explains why motors remain still under small commands
- ✓ Produces realistic settling behavior near target angles
- ✓ Avoids the unphysical assumption of infinite friction at zero velocity

---

## Equation of Motion

### Full Nonlinear Dynamics

The 2nd-order angular acceleration is governed by Newton's 2nd law for rotation:

$$J \, \ddot{\theta}(t) = T_m(t) - T_f(\dot{\theta}, T_m) - T_v(\dot{\theta})$$

where:
- $T_m = u(t) \cdot T_{\max}$ is the commanded motor torque
- $T_f$ is the nonlinear friction torque (defined above)
- $T_v = c \, \dot{\theta}$ is the viscous damping torque

### Rearranged Form (Standard for Analysis)

$$\ddot{\theta}(t) = \frac{1}{J} \left[ T_m(t) - T_f(\dot{\theta}, T_m) - c \, \dot{\theta}(t) \right]$$

### Simplified in the Kinetic (Sliding) Regime

When the motor is actively sliding (overcoming kinetic friction), the friction torque reduces to:
$$T_f = -\text{sgn}(\dot{\theta}) \cdot T_d$$

and the equation becomes:

$$\ddot{\theta}(t) = \frac{1}{J} \left[ u(t) \cdot T_{\max} + \text{sgn}(\dot{\theta}) \cdot T_d - c \, \dot{\theta}(t) \right]$$

### Graphical Interpretation

The friction characteristic is a **hysteretic dead-zone**:

```
    T_f (friction torque)
     │
   T_d├───────┐
     │        │╱ (sliding with ω̇ > 0)
     │        ╱
     │       ╱
  ───┼──────┼─────── T_m (motor torque)
     │     ╱
     │    ╱  (stiction: T_f follows T_m)
     │   ╱
    -T_d└───────┐  (sliding with ω̇ < 0)
     │
```

The width of the stiction band is $2T_s$; the kinetic regime saturates at $\pm T_d$.

---

## Hard Mechanical Limits

### Boundary Enforcement

Physical servos have hard mechanical stops at extreme angles. The model enforces:

$$\theta_{\min} \leq \theta(t) \leq \theta_{\max}$$

Where axis-dependent limits are:
- **Pan axis** (azimuth): $\theta_{\min} = -\pi$ rad ($-180°$), $\theta_{\max} = +\pi$ rad ($+180°$)
- **Tilt axis** (elevation): $\theta_{\min} = -\pi/2$ rad ($-90°$), $\theta_{\max} = +\pi/2$ rad ($+90°$)

### Velocity Clipping at Limits

When the integrated angle exceeds a limit, **active velocity suppression** occurs:

$$\theta(t) = \begin{cases}
\theta_{\max} & \text{if } \theta_{\text{proposed}} > \theta_{\max} \\
\theta_{\min} & \text{if } \theta_{\text{proposed}} < \theta_{\min} \\
\theta_{\text{proposed}} & \text{otherwise}
\end{cases}$$

Simultaneously:

$$\dot{\theta}(t) = \begin{cases}
0 & \text{if } \theta(t) \in \{\theta_{\min}, \theta_{\max}\} \\
\dot{\theta}_{\text{proposed}} & \text{otherwise}
\end{cases}$$

### Physical Interpretation

When the motor hits a hard stop:
- Angle **saturates** at the limit
- Velocity **instantaneously drops to zero** (inelastic collision assumption)
- Further motor torque is "wasted" against the mechanical barrier

This represents a **hard stop event** that can be logged for diagnosis.

---

## Energy Accounting

### Control Effort as Energy Proxy

The cumulative control effort is computed as:

$$E(t) = \int_0^t |u(\tau)|^2 \, d\tau$$

In discrete form (Euler integration):

$$E[k+1] = E[k] + u[k]^2 \cdot \Delta t$$

### Physical Interpretation

- **Interpretation:** $E(t)$ represents the squared control signal integrated over time, serving as a proxy for **cumulative electrical power dissipation** or **actuation effort**.
- **Units:** Dimensionless (or [Volts²⋅seconds] if control signal is a normalized voltage)
- **Use Case:** Track cumulative energy consumption; higher $E$ indicates more total control action was required (e.g., fighting friction, compensating for disturbances)

### Why Squared Control Effort?

The term $u^2$ naturally penalizes large control signals more than small ones:
- A control input of $u = 0.5$ contributes $0.25$ per unit time
- A control input of $u = 1.0$ contributes $1.0$ per unit time (4× more expensive)

This aligns with electrical reality: Power dissipation in a resistor is proportional to $V^2$.

### Energy as a Diagnostic

By monitoring $\Delta E$ (energy step per control cycle), the controller can:
- Detect excessive control effort (sign of instability or disturbance)
- Tune gains to minimize cumulative energy
- Identify periods of high friction (large $\Delta E$ despite small desired acceleration)

---

## Implementation Notes

### Numerical Integration Strategy

The model uses **explicit Euler integration**:

$$\dot{\theta}[k+1] = \dot{\theta}[k] + \ddot{\theta}[k] \cdot \Delta t$$
$$\theta[k+1] = \theta[k] + \dot{\theta}[k] \cdot \Delta t$$

**Note:** This is 1st-order accurate. For stiff systems or very small friction, consider RK4 or implicit methods.

### Sign Convention

- **Positive $u$:** Motor accelerates in positive direction (counterclockwise, typically)
- **Positive $\theta$:** Angular position increases
- **Positive $\dot{\theta}$:** Motor rotating in positive direction
- **Friction opposes velocity:** Always directed to slow the rotor

### Parameter Tuning Guidance

| Parameter | Typical Range | Notes |
|-----------|---------------|-------|
| $J$ | $10^{-5}$ to $10^{-3}$ kg⋅m² | Depends on rotor mass and load |
| $T_{\max}$ | $0.1$ to $1.0$ N⋅m | MG996R spec: 0.35 N⋅m at 6V |
| $T_s$ | $0.01$ to $0.1 \cdot T_d$ | Typically 1.3–1.5× $T_d$ |
| $T_d$ | $0.01$ to $0.05 \cdot T_{\max}$ | Often ~5% of peak torque |
| $c$ | $0.001$ to $0.1$ N⋅m⋅s/rad | High = sluggish, low = twitchy |
| $\omega_d$ | $0.01$ to $0.1$ rad/s | Defines stiction band width |

### Validation Checklist

✓ Control signal is properly normalized to $[-1, +1]$  
✓ Angle limits match physical hardware  
✓ Friction torques are always opposing velocity (except in stiction)  
✓ Energy is monotonically increasing  
✓ Hard stops zero velocity immediately  
✓ Stiction can hold motor at rest when $|u| < T_s / T_{\max}$  

---

## Example: Manual Calculation

**Scenario:** Pan axis with $\omega \approx 0.5$ rad/s (in positive direction), $u = 0.3$.

**Given Parameters:**
- $T_{\max} = 0.35$ N⋅m
- $J = 0.00015$ kg⋅m²
- $T_d = 0.015$ N⋅m
- $c = 0.01$ N⋅m⋅s/rad
- $\omega_d = 0.05$ rad/s (deadband)

**Calculation:**

1. Motor torque: $T_m = 0.3 \times 0.35 = 0.105$ N⋅m

2. Stiction check: $|\omega| = 0.5 > 0.05$, so **kinetic regime**

3. Friction torque: $T_f = -\text{sgn}(0.5) \times 0.015 = -0.015$ N⋅m

4. Viscous torque: $T_v = 0.01 \times 0.5 = 0.005$ N⋅m

5. Net torque: $T_{\text{net}} = 0.105 - (-0.015) - 0.005 = 0.115$ N⋅m

6. Angular acceleration: $\ddot{\theta} = \frac{0.115}{0.00015} \approx 767$ rad/s²

7. Velocity update (dt = 0.01 s): $\dot{\theta}_{\text{new}} = 0.5 + 767 \times 0.01 = 8.17$ rad/s (rapid spin-up)

8. Energy step: $\Delta E = 0.3^2 \times 0.01 = 0.0009$ J⋅s (negligible)

---

## References & Standards

- **IEEE 1415-2015:** Guide for the Measurement of Rotating-Machinery Vibration
- **ANSI/ITEC 1–7 (2018):** Servo Motor Performance Standards
- **Nonlinear Systems Theory (Khalil, 2002):** Chapter 3 (Lyapunov stability)
- **Control Systems Design (Nise, 2020):** State-space modeling and friction

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-20 | Initial thesis-level documentation |

