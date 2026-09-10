(() => {
  'use strict';
  const config = window.ZHOUJI_CONFIG || {};
  const safeURL = (value) => {
    try { const url = new URL(value); return url.protocol === 'https:' ? url.href : null; }
    catch { return null; }
  };
  const appStoreURL = safeURL(config.appStoreUrl);
  const storeLink = document.querySelector('#app-store-link');
  if (appStoreURL && new URL(appStoreURL).hostname === 'apps.apple.com') {
    document.querySelectorAll('.store-button').forEach(link => {
      link.href = appStoreURL;
      link.removeAttribute('aria-disabled');
    });
    document.querySelector('#download-label').textContent = 'App Store 下载';
    document.querySelector('#download-status').textContent = '适用于 iPhone · iOS 17 及以上';
  } else {
    storeLink.addEventListener('click', event => {
      event.preventDefault();
      document.querySelector('#download-status').textContent = '粥记正在准备上架，敬请期待。';
    });
  }
  document.querySelector('#download-status').setAttribute('role', 'status');
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(config.contactEmail || '')) {
    const contact = document.querySelector('#contact-link');
    contact.href = `mailto:${config.contactEmail}`;
    contact.hidden = false;
  }

  const checkboxes = [...document.querySelectorAll('.goal-tasks input')];
  const updateProgress = () => {
    const count = checkboxes.filter(input => input.checked).length;
    document.querySelector('#goal-progress').value = count;
    document.querySelector('#goal-progress').textContent = `${count * 20}%`;
    document.querySelector('#goal-percent').textContent = `${count * 20}%`;
  };
  checkboxes.forEach(input => input.addEventListener('change', updateProgress));
  document.querySelector('#goal-percent').setAttribute('aria-live', 'polite');

  // This demonstration uses elapsed time instead of counting interval ticks.
  let elapsed = 42 * 60 + 18;
  let startedAt = performance.now();
  let running = true;
  const timerButton = document.querySelector('#timer-toggle');
  const renderTimer = () => {
    const seconds = Math.floor(elapsed + (running ? (performance.now() - startedAt) / 1000 : 0));
    const minutes = Math.floor(seconds / 60);
    document.querySelector('#timer-digits').textContent = `${String(minutes).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  };
  timerButton.addEventListener('click', () => {
    if (running) elapsed += (performance.now() - startedAt) / 1000;
    else startedAt = performance.now();
    running = !running;
    timerButton.setAttribute('aria-pressed', String(!running));
    timerButton.setAttribute('aria-label', running ? '暂停专注演示' : '继续专注演示');
    document.querySelector('#timer-status').textContent = running ? '正在专注 · 完成论文' : '已暂停 · 休息一下';
    renderTimer();
  });
  setInterval(renderTimer, 1000);

  const dialog = document.querySelector('#info-dialog');
  const messages = {
    privacy: { title: '隐私说明', paragraphs: ['本官网用于展示粥记的功能，不要求注册，不设置数据收集表单，也没有接入统计或广告脚本。', '页面中的目标勾选和专注计时仅为互动演示，刷新页面后重置，不会写入粥记 App。网站托管服务可能保留正常访问所需的技术日志。', '粥记 App 的任务、目标与计时记录保存在设备本地。正式隐私政策将在上架时提供。'] },
    usage: { title: '简单开始使用粥记', paragraphs: ['在“今天”记下一件要做的事，完成后打勾。未完成的任务会继续保留，无需每天重新添加。', '把相关任务放进一个目标，完成进度会随任务自动更新。想专注时开始计时，可以暂停、继续或结束。', '在“记录”回顾真实完成的任务和投入时间。网页中的手机画面与互动为功能示意，请以实际 App 为准。'] },
  };
  document.querySelectorAll('[data-dialog]').forEach(button => {
    button.addEventListener('click', () => {
      const name = button.dataset.dialog;
      const external = safeURL(name === 'privacy' ? config.privacyUrl : config.termsUrl);
      if (external) { window.location.assign(external); return; }
      const message = messages[name];
      document.querySelector('#dialog-title').textContent = message.title;
      document.querySelector('#dialog-content').replaceChildren(...message.paragraphs.map(text => {
        const paragraph = document.createElement('p');
        paragraph.textContent = text;
        return paragraph;
      }));
      dialog.showModal();
    });
  });
  document.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) {
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close();
  }});
})();
