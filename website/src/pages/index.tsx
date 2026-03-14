import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <p className={styles.heroDescription}>
          Build, archive, and publish apps to the App Store — from Xcode archive to App Review submission.
          Manage versions, localizations, screenshots, provisioning, in-app purchases, and subscriptions.
        </p>
        <div className={styles.buttons}>
          <Link
            className="button button--primary button--lg"
            to="/docs/getting-started/installation">
            Get Started
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
            <Heading as="h2" className="text--center">Install</Heading>
            <CodeBlock language="bash">
              {`brew tap keremerkan/tap\nbrew install asc-cli`}
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

const features: FeatureItem[] = [
  {
    title: 'Full Release Pipeline',
    description: (
      <>
        Archive, upload, manage versions and localizations, attach builds,
        run preflight checks, and submit for App Review — all from the terminal.
      </>
    ),
  },
  {
    title: 'Provisioning Management',
    description: (
      <>
        Register devices, create certificates, manage bundle IDs and capabilities,
        create and reissue provisioning profiles. Most commands support interactive mode.
      </>
    ),
  },
  {
    title: 'Screenshots & Media',
    description: (
      <>
        Upload and download screenshots and app previews with a simple folder structure.
        Works with zip files and integrates with{' '}
        <Link to="https://github.com/keremerkan/asc-screenshots">asc-screenshots</Link>.
      </>
    ),
  },
  {
    title: 'In-App Purchases & Subscriptions',
    description: (
      <>
        List, create, update, and delete IAPs and subscriptions.
        Manage localizations and submit for review alongside your app version.
      </>
    ),
  },
  {
    title: 'Workflows & Automation',
    description: (
      <>
        Chain commands into workflow files for repeatable release processes.
        Use <code>--yes</code> for fully unattended CI/CD execution.
      </>
    ),
  },
  {
    title: 'AI-Ready',
    description: (
      <>
        Ships with a skill file that gives AI coding agents (Claude Code, Cursor,
        Windsurf, GitHub Copilot) full knowledge of all commands and workflows.
      </>
    ),
  },
];

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
      title="A Swift CLI for App Store Connect"
      description="A command-line tool for building, archiving, and publishing apps to the App Store.">
      <HomepageHeader />
      <main>
        <InstallSection />
        <FeaturesSection />
      </main>
    </Layout>
  );
}
