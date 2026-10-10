# ============================================================
# Dot Product Visualization — Full GPU Reduction
# Shows parallel multiply phase AND reduction tree
# ============================================================

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.lines as mlines
import numpy as np
import os


def read_file(filename):
    data = {}
    partials = []
    vec_a = []; vec_b = []

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(',')

            if parts[0].isdigit():
                vec_a.append(int(parts[1]))
                vec_b.append(int(parts[2]))
                partials.append(int(parts[3]))
            elif parts[0] == 'round1':
                data['round1'] = [int(x) for x in parts[1:]]
            elif parts[0] == 'round2':
                data['round2'] = [int(x) for x in parts[1:]]
            elif parts[0] == 'final':
                data['final'] = int(parts[1])
            elif parts[0] == 'expected':
                data['expected'] = int(parts[1])
            elif parts[0] == 'mul_cycles':
                data['mul_cycles'] = int(parts[1])
            elif parts[0] == 'reduce_cycles':
                data['reduce_cycles'] = int(parts[1])
            elif parts[0] == 'total_cycles':
                data['total_cycles'] = int(parts[1])

    data['partials'] = partials
    data['vec_a']    = vec_a
    data['vec_b']    = vec_b
    return data


def draw_node(ax, x, y, text, color='#58A6FF', size=0.35):
    circle = plt.Circle((x, y), size,
                         facecolor=color,
                         edgecolor='white',
                         linewidth=1.5, zorder=3)
    ax.add_patch(circle)
    ax.text(x, y, text, ha='center', va='center',
            color='white', fontsize=8,
            fontweight='bold', zorder=4)


def draw_arrow(ax, x1, y1, x2, y2):
    ax.annotate('', xy=(x2, y2+0.35),
                xytext=(x1, y1-0.35),
                arrowprops=dict(
                    arrowstyle='->', color='#8B949E',
                    lw=1.2),
                zorder=2)


def create_visualization(data):
    fig = plt.figure(figsize=(18, 10))
    fig.patch.set_facecolor('#0D1117')
    fig.suptitle(
        'Mini GPU Simulator — Dot Product: '
        'Parallel Multiply + Tree Reduction',
        fontsize=16, fontweight='bold',
        color='white', y=0.98)

    # ── Panel 1: Partial products bar chart ───────────────────
    ax1 = fig.add_subplot(1, 3, 1)
    ax1.set_facecolor('#161B22')

    partials = data['partials']
    vec_a    = data['vec_a']
    vec_b    = data['vec_b']
    colors   = ['#58A6FF' if i%2==0 else '#3FB950'
                for i in range(8)]

    bars = ax1.bar(range(8), partials,
                   color=colors, edgecolor='white',
                   linewidth=0.5)
    for bar, val in zip(bars, partials):
        ax1.text(bar.get_x() + bar.get_width()/2,
                 bar.get_height() + 0.2,
                 str(val), ha='center', va='bottom',
                 color='white', fontweight='bold',
                 fontsize=10)

    ax1.set_title(
        'Phase 1: Parallel MUL\n'
        '8 cores execute simultaneously\n'
        f'({data.get("mul_cycles","?")} measured demo cycles)',
        color='white', fontsize=10)
    ax1.set_xlabel('Core ID', color='white')
    ax1.set_ylabel('A[i] × B[i]', color='white')
    ax1.set_xticks(range(8))
    ax1.set_xticklabels(
        [f'C{i}\n{vec_a[i]}×{vec_b[i]}'
         for i in range(8)],
        color='white', fontsize=8)
    ax1.tick_params(colors='white')
    for sp in ['top','right']:
        ax1.spines[sp].set_visible(False)
    for sp in ['bottom','left']:
        ax1.spines[sp].set_color('#30363D')
    ax1.set_ylim(0, max(partials)*1.35)

    # ── Panel 2: Reduction tree ────────────────────────────────
    ax2 = fig.add_subplot(1, 3, 2)
    ax2.set_facecolor('#161B22')
    ax2.set_xlim(-0.5, 8.5)
    ax2.set_ylim(0, 10)
    ax2.axis('off')
    ax2.set_title(
        'Phase 2: Tree Reduction on GPU\n'
        '3 GPU ADD rounds: 8 → 4 → 2 → 1\n'
        f'({data.get("reduce_cycles","?")} measured demo cycles)',
        color='white', fontsize=10)

    # Level 0: partial products (8 nodes)
    level0_x = [0.5+i for i in range(8)]
    level0_y = 8.5
    for i, (x, val) in enumerate(zip(level0_x, partials)):
        draw_node(ax2, x, level0_y, str(val),
                  color='#58A6FF' if i%2==0 else '#3FB950')

    # Level 1 label
    ax2.text(-0.3, level0_y, 'MUL\nresults',
             color='#8B949E', fontsize=7,
             va='center')

    # Round 1: 4 ADD nodes
    r1      = data.get('round1', [0,0,0,0])
    r1_x    = [1.0, 3.0, 5.0, 7.0]
    r1_y    = 6.0
    r1_pairs = [(0,1),(2,3),(4,5),(6,7)]

    for i, (x, val) in enumerate(zip(r1_x, r1)):
        draw_node(ax2, x, r1_y, str(val),
                  color='#F0E68C')
        # Arrows from two parents
        p0, p1 = r1_pairs[i]
        draw_arrow(ax2, level0_x[p0], level0_y,
                   x, r1_y)
        draw_arrow(ax2, level0_x[p1], level0_y,
                   x, r1_y)

    ax2.text(-0.3, r1_y, 'Round\n1',
             color='#8B949E', fontsize=7, va='center')

    # Round 2: 2 ADD nodes
    r2   = data.get('round2', [0,0])
    r2_x = [2.0, 6.0]
    r2_y = 3.5

    for i, (x, val) in enumerate(zip(r2_x, r2)):
        draw_node(ax2, x, r2_y, str(val),
                  color='#FF7B72')
        draw_arrow(ax2, r1_x[i*2],   r1_y, x, r2_y)
        draw_arrow(ax2, r1_x[i*2+1], r1_y, x, r2_y)

    ax2.text(-0.3, r2_y, 'Round\n2',
             color='#8B949E', fontsize=7, va='center')

    # Round 3: final sum
    final = data.get('final', 0)
    f_x   = 4.0
    f_y   = 1.2

    draw_node(ax2, f_x, f_y, str(final),
              color='#3FB950', size=0.5)
    draw_arrow(ax2, r2_x[0], r2_y, f_x, f_y)
    draw_arrow(ax2, r2_x[1], r2_y, f_x, f_y)

    ax2.text(-0.3, f_y, 'Final',
             color='#8B949E', fontsize=7, va='center')

    correct = data.get('expected', 120)
    status  = '✓ CORRECT' if final == correct else '✗ WRONG'
    color   = '#3FB950'    if final == correct else '#FF7B72'
    ax2.text(f_x, f_y - 0.9,
             f'= {final} {status}',
             ha='center', color=color,
             fontsize=10, fontweight='bold')

    # ── Panel 3: Timing and summary ───────────────────────────
    ax3 = fig.add_subplot(1, 3, 3)
    ax3.set_facecolor('#161B22')
    ax3.axis('off')
    ax3.set_title('Performance Summary',
                  color='white', fontsize=10)

    mul_cyc    = data.get('mul_cycles',    0)
    red_cyc    = data.get('reduce_cycles', 0)
    total_cyc  = data.get('total_cycles',  0)

    # Timing bar chart embedded in ax3
    phases  = ['MUL\nPhase', 'Reduce\nPhase']
    cyc_val = [mul_cyc, red_cyc]
    ypos    = [0.82, 0.72]
    maxval  = max(cyc_val) if max(cyc_val) > 0 else 1

    ax3.text(0.5, 0.95, 'Measured Clock Cycles',
             transform=ax3.transAxes,
             ha='center', color='white',
             fontsize=9, fontweight='bold')

    bar_colors = ['#58A6FF', '#F0E68C']
    for i, (phase, val, y, bc) in enumerate(
            zip(phases, cyc_val, ypos, bar_colors)):
        bar_w = (val / maxval) * 0.55
        rect  = mpatches.FancyBboxPatch(
            (0.1, y-0.025), bar_w, 0.045,
            boxstyle='round,pad=0.005',
            facecolor=bc, edgecolor='none',
            transform=ax3.transAxes, zorder=3)
        ax3.add_patch(rect)
        ax3.text(0.1+bar_w+0.02, y,
                 f'{phase}: {val} cycles',
                 transform=ax3.transAxes,
                 va='center', color='white',
                 fontsize=8)

    # Stats table
    stats = [
        ('Vectors',        'A·B (8 elements)'),
        ('Dot product',    str(final)),
        ('Expected',       str(correct)),
        ('Expected',       str(sum(a*b for a,b in
                                   zip(vec_a, vec_b)))),
        ('Status',         '✓ CORRECT'
                           if final == sum(a*b for a,b in
                               zip(vec_a, vec_b))
                           else '✗ WRONG'),
        ('MUL cycles',     str(mul_cyc)),
        ('Reduce cycles',  str(red_cyc)),
        ('Total cycles',   str(total_cyc)),
        ('Reduce order',   'O(log₂8) = 3'),
        ('Cores',          '8'),
        ('Architecture',   'SIMD + Tree'),
    ]

    y = 0.60
    for key, val in stats:
        is_status  = key == 'Status'
        is_result  = key in ['Dot product','Total cycles']
        text_color = ('#3FB950' if is_status
                               and '✓' in val
                      else '#FF7B72' if is_status
                      else '#58A6FF' if is_result
                      else 'white')
        ax3.text(0.05, y, f'{key}:',
                 transform=ax3.transAxes,
                 fontsize=9, color='#8B949E',
                 va='top')
        ax3.text(0.50, y, val,
                 transform=ax3.transAxes,
                 fontsize=9, color=text_color,
                 va='top', fontweight='bold')
        y -= 0.055

    fig.text(
        0.5, 0.01,
        'Mini GPU Simulator | '
        'Built from scratch: Gates→ALU→Cores | '
        'github.com/Saurabh8793/mini-GPU-verilog',
        ha='center', fontsize=7, color='#8B949E')

    plt.tight_layout(rect=[0, 0.03, 1, 0.95])

    os.makedirs('output', exist_ok=True)
    plt.savefig('output/dot_product.png',
                dpi=150, bbox_inches='tight',
                facecolor='#0D1117')
    print("Saved: output/dot_product.png")
    plt.show()


def main():
    # Resolve path relative to this script: python/ → ../ → RTL/dot_product.hex
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fname = os.path.join(script_dir, '..', 'RTL', 'dot_product.hex')
    if not os.path.exists(fname):
        print(f"ERROR: {fname} not found")
        print("Run simulation first: vvp dp_demo")
        return

    print("Reading dot_product.hex...")
    data = read_file(fname)
    print(f"Partials:  {data['partials']}")
    print(f"Round 1:   {data.get('round1')}")
    print(f"Round 2:   {data.get('round2')}")
    print(f"Final:     {data.get('final')}")
    print(f"Cycles:    {data.get('total_cycles')}")
    expected = sum(a*b for a,b in zip(
        data['vec_a'], data['vec_b']))
    print(f"Expected:  {expected}")
    print(f"Correct:   {data.get('final') == expected}")
    create_visualization(data)


if __name__ == '__main__':
    main()