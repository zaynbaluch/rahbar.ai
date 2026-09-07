const header = document.querySelector('[data-header]');
const menu = document.querySelector('[data-menu]');
const nav = document.querySelector('[data-nav]');
const progress = document.querySelector('[data-progress]');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const syncChrome = () => {
  const y = window.scrollY;
  header?.classList.toggle('scrolled', y > 14);

  if (progress) {
    const page = document.documentElement;
    const max = Math.max(1, page.scrollHeight - window.innerHeight);
    progress.style.width = `${Math.min(100, (y / max) * 100)}%`;
  }
};

syncChrome();
window.addEventListener('scroll', syncChrome, { passive: true });

menu?.addEventListener('click', () => {
  const open = nav?.classList.toggle('open') ?? false;
  menu.setAttribute('aria-expanded', String(open));
});

nav?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    nav.classList.remove('open');
    menu?.setAttribute('aria-expanded', 'false');
  });
});

const revealItems = document.querySelectorAll('.reveal');
if (reducedMotion || !('IntersectionObserver' in window)) {
  revealItems.forEach((item) => item.classList.add('visible'));
} else {
  const revealObserver = new IntersectionObserver((entries) => {
    const entering = entries.filter((entry) => entry.isIntersecting);
    entering.forEach((entry, index) => {
      entry.target.style.transitionDelay = `${Math.min(index * 55, 165)}ms`;
      entry.target.classList.add('visible');
      revealObserver.unobserve(entry.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -28px 0px' });

  revealItems.forEach((item) => revealObserver.observe(item));
}

const navLinks = [...document.querySelectorAll('[data-nav-link]')];
const sections = [...document.querySelectorAll('[data-section][id]')];

const setActiveNav = (id) => {
  navLinks.forEach((link) => {
    const active = link.getAttribute('href') === `#${id}`;
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'true');
    else link.removeAttribute('aria-current');
  });
};

if ('IntersectionObserver' in window && sections.length) {
  const activeObserver = new IntersectionObserver((entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio);
    if (visible[0]) setActiveNav(visible[0].target.id);
  }, { rootMargin: '-28% 0px -58% 0px', threshold: [0, 0.1, 0.35, 0.6] });

  sections.forEach((section) => activeObserver.observe(section));
}

const heroVisual = document.querySelector('[data-hero-visual]');
if (heroVisual && !reducedMotion) {
  const resetParallax = () => {
    heroVisual.style.setProperty('--front-x', '0px');
    heroVisual.style.setProperty('--front-y', '0px');
    heroVisual.style.setProperty('--back-x', '0px');
    heroVisual.style.setProperty('--back-y', '0px');
    heroVisual.style.setProperty('--card-x', '0px');
    heroVisual.style.setProperty('--card-y', '0px');
  };

  heroVisual.addEventListener('pointermove', (event) => {
    const rect = heroVisual.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
    const y = ((event.clientY - rect.top) / rect.height - 0.5) * 2;

    heroVisual.style.setProperty('--front-x', `${x * 9}px`);
    heroVisual.style.setProperty('--front-y', `${y * 7}px`);
    heroVisual.style.setProperty('--back-x', `${x * -7}px`);
    heroVisual.style.setProperty('--back-y', `${y * -5}px`);
    heroVisual.style.setProperty('--card-x', `${x * 5}px`);
    heroVisual.style.setProperty('--card-y', `${y * 4}px`);
  });

  heroVisual.addEventListener('pointerleave', resetParallax);
}

const dialog = document.querySelector('[data-lightbox-dialog]');
const dialogImage = dialog?.querySelector('[data-lightbox-image]');
const dialogClose = dialog?.querySelector('[data-lightbox-close]');

const closeDialog = () => {
  if (!dialog) return;
  if (typeof dialog.close === 'function' && dialog.open) dialog.close();
  else dialog.removeAttribute('open');
};

document.querySelectorAll('[data-lightbox]').forEach((button) => {
  button.addEventListener('click', () => {
    if (!dialog || !dialogImage) return;
    dialogImage.src = button.dataset.lightbox;
    dialogImage.alt = button.dataset.alt || 'Bayaz workflow screenshot';
    if (typeof dialog.showModal === 'function') dialog.showModal();
    else dialog.setAttribute('open', '');
  });
});

dialogClose?.addEventListener('click', closeDialog);
dialog?.addEventListener('click', (event) => {
  if (event.target === dialog) closeDialog();
});
