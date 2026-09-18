# Sprint 24.1 — infraestrutura de build Node/Sass.
#
# Expõe o build compilado (app/assets/builds/app.css, gerado por `yarn build:css`)
# e os webfonts do Font Awesome (pacote npm local) ao Propshaft.
Rails.application.config.assets.paths << Rails.root.join("app/assets/builds")
Rails.application.config.assets.paths << Rails.root.join("node_modules/@fortawesome/fontawesome-free/webfonts")
