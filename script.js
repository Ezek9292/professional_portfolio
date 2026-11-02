const menuButton = document.querySelector('.menu-button');
const nav = document.querySelector('#primary-nav');
const navLinks = [...document.querySelectorAll('#primary-nav a[href^="#"]')];
const sections = [...document.querySelectorAll('main section[id]')];
const copyButton = document.querySelector('.copy-email');
const toast = document.querySelector('.toast');

const setMenuOpen = (open) => {
  menuButton.setAttribute('aria-expanded', String(open));
  nav.classList.toggle('open', open);
};

menuButton.addEventListener('click', () => {
  setMenuOpen(menuButton.getAttribute('aria-expanded') !== 'true');
});

navLinks.forEach((link) => link.addEventListener('click', () => setMenuOpen(false)));

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && nav.classList.contains('open')) {
    setMenuOpen(false);
    menuButton.focus();
  }
});

const revealObserver = new IntersectionObserver((entries, observer) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((element) => revealObserver.observe(element));

const sectionObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    navLinks.forEach((link) => {
      link.classList.toggle('active', link.getAttribute('href') === `#${entry.target.id}`);
    });
  });
}, { rootMargin: '-35% 0px -55%', threshold: 0 });

sections.forEach((section) => sectionObserver.observe(section));

let toastTimer;

copyButton.addEventListener('click', async () => {
  const email = copyButton.dataset.email;
  try {
    await navigator.clipboard.writeText(email);
    toast.textContent = 'Email copied';
  } catch {
    toast.textContent = email;
  }
  toast.classList.add('show');
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove('show'), 2200);
});

const contactForm = document.querySelector('.contact-form');
const formStatus = contactForm.querySelector('.form-status');
const submitButton = contactForm.querySelector('button[type="submit"]');

contactForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  submitButton.disabled = true;
  formStatus.classList.remove('error');
  formStatus.textContent = 'Sending...';
  try {
    const response = await fetch(contactForm.action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(Object.fromEntries(new FormData(contactForm))),
    });
    const result = await response.json();
    if (!response.ok || !result.success) throw new Error(result.message);
    contactForm.reset();
    formStatus.textContent = 'Thanks, your message has been sent. I will get back to you soon.';
  } catch (error) {
    formStatus.classList.add('error');
    formStatus.textContent = `Message not sent${error.message ? `: ${error.message}` : ''}. Please try again or copy my email address.`;
  } finally {
    submitButton.disabled = false;
  }
});

document.querySelector('#year').textContent = new Date().getFullYear();
