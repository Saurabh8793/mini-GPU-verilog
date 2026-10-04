# ============================================================
# Triangle Rasterization Visualization
# ============================================================

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.gridspec as gridspec
import numpy as np
import os


def read_pixels(filename, width=64, height=64):
    pixels = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                pixels.append(int(line, 16))
    return np.array(pixels, dtype=np.uint8).reshape(
        height, width)


def verify_edge_function(px, py, v0, v1, v2):
    """Python reference edge function."""
    def edge(ax, ay, bx, by, x, y):
        return (bx-ax)*(y-ay) - (by-ay)*(x-ax)
    e0 = edge(v0[0],v0[1], v1[0],v1[1], px, py)
    e1 = edge(v1[0],v1[1], v2[0],v2[1], px, py)
    e2 = edge(v2[0],v2[1], v0[0],v0[1], px, py)
    return e0 <= 0 and e1 <= 0 and e2 <= 0


def compute_reference(width=64, height=64):
    """Python reference rasterizer."""
    v0 = (32, 4); v1 = (4, 60); v2 = (60, 60)
    image = np.zeros((height, width), dtype=np.uint8)
    for py in range(height):
        for px in range(width):
            if verify_edge_function(px, py, v0, v1, v2):
                image[py, px] = 255
    return image


def create_visualization(gpu_image):
    ref_image = compute_reference()

    # Compare
    match = (gpu_image == ref_image)
    match_pct = match.sum() * 100 // 4096

    fig = plt.figure(figsize=(16, 9))
    fig.patch.set_facecolor('#0D1117')
    fig.suptitle(
        'Mini GPU — Flat Shaded Triangle Rasterization\n'
        '8 Parallel Edge Function Units | '
        'Counter-Clockwise Winding',
        fontsize=14, fontweight='bold',
        color='white', y=0.98)

    gs = gridspec.GridSpec(2, 3, figure=fig,
                           hspace=0.4, wspace=0.3)

    v0=(32,4); v1=(4,60); v2=(60,60)

    def add_triangle(ax):
        tri = plt.Polygon([v0,v1,v2], fill=False,
                          edgecolor='red', linewidth=2)
        ax.add_patch(tri)
        for v, lbl in zip([v0,v1,v2],
                           ['V0(32,4)','V1(4,60)',
                            'V2(60,60)']):
            ax.plot(v[0],v[1],'ro',markersize=5)
            ax.annotate(lbl, v, xytext=(4,4),
                        textcoords='offset points',
                        color='yellow', fontsize=7)

    # Panel 1: GPU output grayscale
    ax1 = fig.add_subplot(gs[0,0])
    ax1.set_facecolor('#0D1117')
    ax1.imshow(gpu_image, cmap='gray',
               interpolation='nearest',
               vmin=0, vmax=255)
    add_triangle(ax1)
    ax1.set_title('GPU Output\n(8 parallel edge units)',
                  color='white', fontsize=10)
    ax1.tick_params(colors='white', labelsize=8)

    # Panel 2: Colored GPU output
    ax2 = fig.add_subplot(gs[0,1])
    ax2.set_facecolor('#0D1117')
    colored = np.zeros((*gpu_image.shape,3),
                       dtype=np.uint8)
    colored[gpu_image>0]  = [64, 156, 255]
    colored[gpu_image==0] = [13, 17, 23]
    ax2.imshow(colored, interpolation='nearest')
    add_triangle(ax2)
    ax2.set_title('GPU Output — Colored\nBlue = Inside',
                  color='white', fontsize=10)
    ax2.tick_params(colors='white', labelsize=8)

    # Panel 3: Reference
    ax3 = fig.add_subplot(gs[0,2])
    ax3.set_facecolor('#0D1117')
    ax3.imshow(ref_image, cmap='gray',
               interpolation='nearest',
               vmin=0, vmax=255)
    add_triangle(ax3)
    ax3.set_title('Python Reference\n(float arithmetic)',
                  color='white', fontsize=10)
    ax3.tick_params(colors='white', labelsize=8)

    # Panel 4: Match/mismatch
    ax4 = fig.add_subplot(gs[1,0])
    ax4.set_facecolor('#0D1117')
    diff_img = np.zeros((*gpu_image.shape,3),
                        dtype=np.uint8)
    diff_img[match]  = [63,185,80]   # green = match
    diff_img[~match] = [248,81,73]   # red   = mismatch
    ax4.imshow(diff_img, interpolation='nearest')
    ax4.set_title(
        f'GPU vs Reference\nGreen=Match '
        f'Red=Miss ({match_pct}% match)',
        color='white', fontsize=10)
    ax4.tick_params(colors='white', labelsize=8)

    # Panel 5: Edge function diagram
    ax5 = fig.add_subplot(gs[1,1])
    ax5.set_facecolor('#161B22')
    ax5.axis('off')
    ax5.set_title('Edge Function Architecture',
                  color='white', fontsize=10)

    lines = [
        ('8 pixel coords loaded', '#8B949E'),
        ('simultaneously', '#8B949E'),
        ('', '#8B949E'),
        ('Core i computes:', '#F0E68C'),
        ('E0=(V1-V0)×(P-V0)', '#58A6FF'),
        ('E1=(V2-V1)×(P-V1)', '#58A6FF'),
        ('E2=(V0-V2)×(P-V2)', '#58A6FF'),
        ('', '#8B949E'),
        ('Inside if:', '#F0E68C'),
        ('E0≤0 ∧ E1≤0 ∧ E2≤0', '#3FB950'),
        ('(CCW winding)', '#8B949E'),
        ('', '#8B949E'),
        ('Multiplier:', '#F0E68C'),
        ('signed_multiplier_16x16', '#58A6FF'),
        ('Uses our hardware MUL', '#3FB950'),
    ]
    y = 0.95
    for text, color in lines:
        ax5.text(0.05, y, text,
                 transform=ax5.transAxes,
                 fontsize=8, color=color, va='top',
                 family='monospace')
        y -= 0.062

    # Panel 6: Stats
    ax6 = fig.add_subplot(gs[1,2])
    ax6.set_facecolor('#161B22')
    ax6.axis('off')
    ax6.set_title('Statistics',
                  color='white', fontsize=10)

    inside  = int((gpu_image>0).sum())
    outside = 4096 - inside

    stats = [
        ('Algorithm',  'Edge function'),
        ('Winding',    'Counter-clockwise'),
        ('Inside test','E0,E1,E2 ≤ 0'),
        ('Vertices',   'V0(32,4)'),
        ('',           'V1(4,60)'),
        ('',           'V2(60,60)'),
        ('Cores',      '8 parallel'),
        ('Inside px',  f'{inside}'),
        ('Outside px', f'{outside}'),
        ('Coverage',   f'{inside*100//4096}%'),
        ('GPU match',  f'{match_pct}%'),
        ('Multiplier', '16-bit signed'),
    ]

    y = 0.96
    for key, val in stats:
        is_match = key == 'GPU match'
        color    = '#3FB950' if is_match else 'white'
        ax6.text(0.05, y, f'{key}:' if key else '',
                 transform=ax6.transAxes,
                 fontsize=8, color='#8B949E', va='top')
        ax6.text(0.50, y, val,
                 transform=ax6.transAxes,
                 fontsize=8, color=color,
                 va='top', fontweight='bold')
        y -= 0.075

    fig.text(
        0.5, 0.005,
        'Mini GPU Simulator | 8 Parallel Edge Function Units | '
        'github.com/Saurabh8793/mini-GPU-verilog',
        ha='center', fontsize=7, color='#8B949E')

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    os.makedirs('output', exist_ok=True)
    plt.savefig('output/triangle.png', dpi=150,
                bbox_inches='tight',
                facecolor='#0D1117')
    print("Saved: output/triangle.png")
    plt.show()


def main():
    # Resolve path relative to this script: python/ -> ../ -> RTL/pixels_tri.hex
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fname = os.path.join(script_dir, '..', 'RTL', 'pixels_tri.hex')
    if not os.path.exists(fname):
        print(f"ERROR: {fname} not found")
        print("Run simulation first: vvp triangle_demo  (from the RTL/ directory)")
        return
    print("Reading pixels_tri.hex...")
    image = read_pixels(fname)
    inside = int((image>0).sum())
    print(f"Inside:  {inside} pixels")
    print(f"Outside: {4096-inside} pixels")
    create_visualization(image)


if __name__ == '__main__':
    main()