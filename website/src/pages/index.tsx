import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';
import Translate, {translate} from '@docusaurus/Translate';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={styles.heroBanner}>
      <div className="container">
        <img src="/img/favicon.svg" alt="ASCelerate" className={styles.heroLogo} />
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className={styles.heroTagline}>
          {translate({id: 'homepage.tagline', message: 'A Swift CLI for App Store Connect'})}
        </p>
        <p className={styles.heroDescription}>
          <Translate id="homepage.hero.description">
            Build, archive, and publish apps to the App Store — from Xcode archive to App Review submission.
            Manage versions, localizations, screenshots, provisioning, in-app purchases, and subscriptions.
          </Translate>
        </p>
        <div className={styles.buttons}>
          <Link
            className="button button--primary button--lg"
            to="/docs/getting-started/installation">
            <Translate id="homepage.hero.getStarted">Get Started</Translate>
          </Link>
          <Link
            className="button button--secondary button--lg"
            to="https://github.com/keremerkan/asc-cli">
            GitHub
          </Link>
        </div>
      </div>
    </header>
  );
}

function InstallSection() {
  return (
    <section className={styles.installSection}>
      <div className="container">
        <div className="row">
          <div className={clsx('col col--6 col--offset-3')}>
            <Heading as="h2" className="text--center">
              <Translate id="homepage.install.title">Install</Translate>
            </Heading>
            <CodeBlock language="bash" title="Homebrew">
              {`brew tap keremerkan/tap\nbrew install ascelerate`}
            </CodeBlock>
            <CodeBlock language="bash" title="curl">
              {`curl -sSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash`}
            </CodeBlock>
          </div>
        </div>
      </div>
    </section>
  );
}

type FeatureItem = {
  title: string;
  description: ReactNode;
};

function getFeatures(): FeatureItem[] {
  return [
    {
      title: translate({id: 'homepage.features.pipeline.title', message: 'Full Release Pipeline'}),
      description: (
        <Translate id="homepage.features.pipeline.description">
          Archive, upload, manage versions and localizations, attach builds,
          run preflight checks, and submit for App Review — all from the terminal.
        </Translate>
      ),
    },
    {
      title: translate({id: 'homepage.features.provisioning.title', message: 'Provisioning Management'}),
      description: (
        <Translate id="homepage.features.provisioning.description">
          Register devices, create certificates, manage bundle IDs and capabilities,
          create and reissue provisioning profiles. Most commands support interactive mode.
        </Translate>
      ),
    },
    {
      title: translate({id: 'homepage.features.media.title', message: 'Screenshots & Media'}),
      description: (
        <>
          <Translate id="homepage.features.media.description">
            Capture screenshots from simulators with dark mode, localization, and status bar overrides.
            Frame screenshots with Apple device bezels.
            Upload and download screenshots and app previews with a simple folder structure.
          </Translate>
        </>
      ),
    },
    {
      title: translate({id: 'homepage.features.iap.title', message: 'In-App Purchases & Subscriptions'}),
      description: (
        <Translate id="homepage.features.iap.description">
          List, create, update, and delete IAPs and subscriptions.
          Manage localizations and submit for review alongside your app version.
        </Translate>
      ),
    },
    {
      title: translate({id: 'homepage.features.workflows.title', message: 'Workflows & Automation'}),
      description: (
        <>
          <Translate id="homepage.features.workflows.description">
            Chain commands into workflow files for repeatable release processes.
            Use --yes for fully unattended CI/CD execution.
          </Translate>
        </>
      ),
    },
    {
      title: translate({id: 'homepage.features.ai.title', message: 'AI-Ready'}),
      description: (
        <Translate id="homepage.features.ai.description">
          Ships with a skill file that gives AI coding agents (Claude Code, Cursor,
          Windsurf, GitHub Copilot) full knowledge of all commands and workflows.
        </Translate>
      ),
    },
  ];
}

function Feature({title, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="padding-horiz--md padding-vert--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

function FeaturesSection() {
  const features = getFeatures();
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {features.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title={translate({id: 'homepage.title', message: 'A Swift CLI for App Store Connect'})}
      description={translate({id: 'homepage.meta.description', message: 'A command-line tool for building, archiving, and publishing apps to the App Store.'})}>
      <HomepageHeader />
      <main>
        <InstallSection />
        <FeaturesSection />
      </main>
    </Layout>
  );
}
