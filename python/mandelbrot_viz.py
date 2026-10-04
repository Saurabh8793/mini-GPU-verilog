# ============================================================
# True Mandelbrot Visualization
# Reads pixels.hex from mandelbrot_demo simulation
# Renders 64x64 true Mandelbrot set image
# ============================================================

import matplotlib.pyplot as plt
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
    arr = np.array(pixels, dtype=np.uint8)
    return arr.reshape(height, width)


def compute_reference(width=64, height=64, max_iter=64):
    """Compute reference Mandelbrot in Python for comparison."""
    image = np.zeros((height, width), dtype=np.uint8)
    for py in range(height):
        for px in range(width):
            c_real = -2.0  + (px / width)  * 2.5
            c_imag = -1.25 + (py / height) * 2.5
            zr, zi = 0.0, 0.0
            it = 0
            while zr*zr + zi*zi <= 4.0 and it < max_iter:
                zr, zi = zr*zr - zi*zi + c_real, \
                          2*zr*zi + c_imag
                it += 1
            if it >= max_iter:
                image[py, px] = 0
            else:
                image[py, px] = int((it / max_iter) * 255)
    return image


def create_visualization(gpu_image, ref_image):
    fig = plt.figure(figsize=(16, 9))
    fig.patch.set_facecolor('#0D1117')

    fig.suptitle(
        'Mini GPU Simulator — True Mandelbrot Set\n'
        'Q8.8 Fixed-Point | 8 Parallel Units | '
        '64×64 Resolution',
        fontsize=15, fontweight='bold',
        color='white', y=0.98)

    gs = gridspec.GridSpec(2, 3, figure=fig,
                           hspace=0.4, wspace=0.3)

    # ── GPU output hot colormap ───────────────────────────────
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.set_facecolor('#0D1117')
    im1 = ax1.imshow(gpu_image, cmap='hot',
                     interpolation='nearest',
                     vmin=0, vmax=255)
    ax1.set_title('GPU Output — Hot Colormap',
                  color='white', fontsize=10)
    ax1.set_xlabel('Real axis', color='white', fontsize=8)
    ax1.set_ylabel('Imaginary axis', color='white', fontsize=8)
    ax1.tick_params(colors='white', labelsize=7)

    # Add axis labels showing complex plane coordinates
    ax1.set_xticks([0, 16, 32, 48, 63])
    ax1.set_xticklabels(['-2.0', '-1.4', '-0.75',
                          '-0.1', '+0.5'],
                         color='white', fontsize=7)
    ax1.set_yticks([0, 16, 32, 48, 63])
    ax1.set_yticklabels(['-1.25', '-0.6', '0.0',
                          '+0.6', '+1.25'],
                         color='white', fontsize=7)

    # ── GPU output inferno colormap ───────────────────────────
    ax2 = fig.add_subplot(gs[0, 1])
    ax2.set_facecolor('#0D1117')
    im2 = ax2.imshow(gpu_image, cmap='inferno',
                     interpolation='nearest',
                     vmin=0, vmax=255)
    ax2.set_title('GPU Output — Inferno Colormap',
                  color='white', fontsize=10)
    ax2.tick_params(colors='white', labelsize=7)
    ax2.set_xticks([0, 32, 63])
    ax2.set_xticklabels(['-2.0', '-0.75', '+0.5'],
                         color='white', fontsize=7)
    ax2.set_yticks([0, 32, 63])
    ax2.set_yticklabels(['-1.25', '0.0', '+1.25'],
                         color='white', fontsize=7)

    # ── Reference Python computation ──────────────────────────
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.set_facecolor('#0D1117')
    im3 = ax3.imshow(ref_image, cmap='hot',
                     interpolation='nearest',
                     vmin=0, vmax=255)
    ax3.set_title('Reference (Python float)\nSame colormap',
                  color='white', fontsize=10)
    ax3.tick_params(colors='white', labelsize=7)
    ax3.set_xticks([0, 32, 63])
    ax3.set_xticklabels(['-2.0', '-0.75', '+0.5'],
                         color='white', fontsize=7)

    # ── Difference image ──────────────────────────────────────
    ax4 = fig.add_subplot(gs[1, 0])
    ax4.set_facecolor('#0D1117')
    diff = np.abs(gpu_image.astype(int) -
                  ref_image.astype(int))
    im4 = ax4.imshow(diff, cmap='RdYlGn_r',
                     interpolation='nearest',
                     vmin=0, vmax=50)
    ax4.set_title(
        f'Difference |GPU - Reference|\n'
        f'Max={diff.max()} Mean={diff.mean():.1f}',
        color='white', fontsize=9)
    ax4.tick_params(colors='white', labelsize=7)
    plt.colorbar(im4, ax=ax4, shrink=0.8,
                 label='Pixel diff').ax.yaxis\
        .set_tick_params(color='white',
                         labelcolor='white')

    # ── Iteration histogram ───────────────────────────────────
    ax5 = fig.add_subplot(gs[1, 1])
    ax5.set_facecolor('#161B22')
    flat = gpu_image.flatten()
    ax5.hist(flat[flat > 0], bins=32,
             color='#FF7B72', edgecolor='none',
             alpha=0.8, label='Escaped')
    ax5.hist(flat[flat == 0], bins=1,
             color='#3FB950', edgecolor='none',
             alpha=0.8, label=f'Inside ({(flat==0).sum()}px)')
    ax5.set_title('Pixel Value Distribution',
                  color='white', fontsize=10)
    ax5.set_xlabel('Pixel Value (0=inside)',
                   color='white', fontsize=8)
    ax5.set_ylabel('Count', color='white', fontsize=8)
    ax5.tick_params(colors='white', labelsize=8)
    ax5.legend(facecolor='#161B22', edgecolor='#30363D',
               labelcolor='white', fontsize=8)
    for sp in ['top', 'right']:
        ax5.spines[sp].set_visible(False)
    for sp in ['bottom', 'left']:
        ax5.spines[sp].set_color('#30363D')

    # ── Architecture info ─────────────────────────────────────
    ax6 = fig.add_subplot(gs[1, 2])
    ax6.set_facecolor('#161B22')
    ax6.axis('off')
    ax6.set_title('Architecture',
                  color='white', fontsize=10)

    inside_count  = int((gpu_image == 0).sum())
    escaped_count = DEPTH - inside_count
    match_count   = int((diff < 10).sum())

    info = [
        ('Algorithm',   'True Mandelbrot'),
        ('Datapath',    'Q8.8 fixed-point'),
        ('Integer bits','8'),
        ('Frac bits',   '8'),
        ('Max iter',    '64'),
        ('Resolution',  '64 × 64'),
        ('Total pixels','4096'),
        ('Inside set',  str(inside_count)),
        ('Escaped',     str(escaped_count)),
        ('GPU matches', f'{match_count}/4096'),
        ('Max pixel diff', str(diff.max())),
        ('Units',       '8 parallel'),
        ('Pixel format','8-bit (0-255)'),
        ('Framebuffer', '8-bit × 4096'),
    ]

    y = 0.97
    for key, val in info:
        is_highlight = key in ['Algorithm', 'Datapath',
                                'GPU matches']
        color = '#3FB950' if is_highlight else 'white'
        ax6.text(0.03, y, f'{key}:',
                 transform=ax6.transAxes,
                 fontsize=8, color='#8B949E', va='top')
        ax6.text(0.52, y, val,
                 transform=ax6.transAxes,
                 fontsize=8, color=color,
                 va='top', fontweight='bold')
        y -= 0.065

    fig.text(
        0.5, 0.005,
        'Mini GPU Simulator | 8-bit GPU + Q8.8 '
        'Fixed-Point Mandelbrot Unit | '
        'github.com/Saurabh8793/mini-GPU-verilog',
        ha='center', fontsize=7, color='#8B949E')

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])

    os.makedirs('output', exist_ok=True)
    plt.savefig('output/mandelbrot.png',
                dpi=150, bbox_inches='tight',
                facecolor='#0D1117')
    print("Saved: output/mandelbrot.png")
    plt.show()


DEPTH = 64 * 64


def main():
    # Resolve path relative to this script:
    #   python/ -> ../ -> RTL/ -> pixels.hex
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fname = os.path.join(script_dir, '..', 'RTL', 'pixels.hex')
    if not os.path.exists(fname):
        print(f"ERROR: {fname} not found")
        print("Run simulation first: vvp mandelbrot_demo  (from the RTL/ directory)")
        return

    print("Reading pixels.hex...")
    gpu_image = read_pixels(fname)
    print(f"GPU image shape:  {gpu_image.shape}")
    print(f"Min: {gpu_image.min()}  "
          f"Max: {gpu_image.max()}  "
          f"Mean: {gpu_image.mean():.1f}")
    print(f"Inside set (black): {(gpu_image==0).sum()} pixels")

    print("Computing Python reference...")
    ref_image = compute_reference()
    print(f"Reference computed")

    diff = np.abs(gpu_image.astype(int) -
                  ref_image.astype(int))
    print(f"Max difference: {diff.max()}")
    print(f"Mean difference: {diff.mean():.2f}")
    print(f"Pixels within 10: {(diff<10).sum()}/4096")

    create_visualization(gpu_image, ref_image)


if __name__ == '__main__':
    main()